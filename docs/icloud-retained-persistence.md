# Retained iCloud persistence

## Storage and migration

[RetainedReminderRepository](../Packages/NotificationManagerCore/Sources/NotificationManagerPersistence/RetainedCloud/RetainedReminderRepository.swift#L7)
is the application source of truth. Its atomic local archive lives beside the
existing SwiftData store, with the suffix `.retained-v1.json`. The archive is
ordinary application support data, independent of the account-bound mirror. It
contains immutable versions, causal parent IDs, raw payload bytes, account-scoped
receipts, the device preference, and account-scoped engine/import cursors.

[ModelContainerFactory](../Packages/NotificationManagerCore/Sources/NotificationManagerPersistence/SwiftData/ModelContainerFactory.swift#L4)
opens the existing version-1 SQLite store with CloudKit disabled. No automatic
mirror is created before account verification. The first archive creation copies
all existing reminders and tags, retaining their UUIDs, relationships, and exact
schedule bytes. Unsupported and corrupt schedules are copied without encoding a
replacement. Duplicate legacy UUIDs become separate recovery versions. The
original SQLite store and its CloudKit records are retained; there is no store,
zone, or production-record purge. A corrupt or unsupported archive stops startup
with the existing data-unavailable recovery UI instead of creating an empty file.
Production scenes use a shared repository actor to serialize local writes.

A read-only [legacy importer](../Packages/NotificationManagerCore/Sources/NotificationManagerPersistence/RetainedCloud/LegacyCloudRecord.swift#L5)
also reads the existing Core Data CloudKit zone after account approval. It maps
reminder/tag records and many-to-many CDMR relationships, copies encrypted values
and asset contents, and retains opaque record recovery copies. Each fetched page
and its cursor save together. Legacy deletions become causal tombstones;
concurrent local values remain recoverable. An expired cursor triggers one fresh
fetch without erasing retained data.

Compatibility is deliberately one-way: upgraded devices read existing legacy
records, including later legacy edits, but write new immutable records in the
separate `PunctualRetainedV1` zone. Old app versions cannot read new changes.
The iCloud settings explanation states this. Upgrade all devices before relying
on cross-device editing; do not operate old and upgraded versions as equivalent
writers. Unsupported legacy record shapes remain in the raw recovery archive
until a decoder supports them. Missing records alone never erase retained data.
Data already purged before this upgrade cannot be reconstructed from an absent
local store; it can only be recovered if still available in the original cloud
account or another backup.

## Account and conflict behavior

The in-app switch is a per-device preference in the local archive, absent from
cloud payloads. An unspecified preference requests sync, but grants no permission
to publish unidentified local data. Signed-out/restricted states retain all data
and permit publication after a local save. Offline or indeterminate identity does
not imply a different account and does not permit cloud-mode publication.

Container ID, build environment and the real container user-record name scope
receipts and engine state. Archived receipts alone do not open the gate after
process restart: visible heads are re-read from the current signed CloudKit
database and their exact payloads verified. A positively missing saved record
invalidates cached receipts and queues retained versions again. This also avoids
trusting a receipt from a differently signed CloudKit environment. Launch/resume,
account notifications, network recovery, local edits, manual retry, and CloudKit notifications invoke a verified sync pass.
The [sync service](../Packages/NotificationManagerCore/Sources/NotificationManagerPersistence/RetainedCloud/RetainedCloudSyncService.swift#L5)
uses manual CKSyncEngine scheduling. It never enables automatic resumption into a
new account. The account is checked before engine creation and immediately before
supplying or acknowledging records. Account changes invalidate the active engine
and gate; late events from an older engine cannot acknowledge the current account.

If retained values have no verified origin, or the current account differs from
the last approved account, the root app presents a confirmation after launch or
resume. The explanation covers reminders, tags, display preferences, and recovery
versions. Acceptance authorizes their merge/publication into that account.
Refusal durably sets the app switch OFF, including after relaunch and resume.
Enabling it again explicitly restarts verification. Unknown identity never clears
the stored approved account. A fresh empty installation needs no data-transfer
confirmation.

Each reminder, tag, and global customization has an immutable revision DAG.
Edits record observed parents; concurrent branches remain distinct. A deterministic
UUID ordering chooses a visible head, independent of device wall clocks. Every
superseded differing value stays in the recovery archive. Settings exposes these
versions, including deletion markers and opaque payload bytes. Selecting a
recovery version creates a new causal version and keeps previous copies. This is
whole-value conflict recovery, not automatic field-by-field reconciliation.

## Application integration

The Sendable [ReminderCloudCommitChecking](../Packages/NotificationManagerCore/Sources/NotificationManagerApplication/Ports/ReminderCloudCommitChecking.swift#L6)
port provides asynchronous `canPublish(_:)` and `changes()`. The production
repository implements it directly. The gate compares the complete current
snapshot, the current immutable revision fingerprint and the verified account.
It also requires selected tag/global-setting revisions to be committed. Identical
device timestamps are not receipts. Acknowledging an older revision cannot release
a newer edit. The stream yields initially and when durable values, receipts or
policy change; consumers should re-read the latest desired state on every signal.

Sync OFF or a positively known signed-out/restricted system state permits the
exact durable local snapshot. Cloud mode requires a matching immutable-record
save result or a verified cloud import. A Core Data export-success notification
never opens this gate. Cloud imports temporarily close the gate until the complete
fetch finishes, avoiding publication from a partially imported causal graph.
API outbox intents, job IDs, revision counters and activity tokens remain local to
the coordinating integration and never enter cloud payloads.

[DisplayCustomizationRepository](../Packages/NotificationManagerCore/Sources/NotificationManagerApplication/Ports/ReminderCloudCommitChecking.swift#L11)
reads/writes opaque global data and per-reminder overrides. The domain shapes are
[DisplayCustomization](../Packages/NotificationManagerCore/Sources/NotificationManagerDomain/Customization/DisplayCustomization.swift#L13)
and [DisplayTemplate](../Packages/NotificationManagerCore/Sources/NotificationManagerDomain/Customization/DisplayCustomization.swift#L3).
Version 1 supplies optional notification and Live Activity title/body templates.
A nil reminder surface inherits the global surface; a nil global surface inherits
the built-in appearance. Rendering and purchase checks belong to the app
integration. Unsupported/corrupt customization bytes remain intact on metadata
edits, imports and restart. Editors must inspect raw data before offering a
supported editor: a non-nil opaque payload that does not decode must not be treated
as an empty setting. Purchase entitlements are not part of this data model.

## Deployment and recovery

Before a production rollout, create/promote the additive `PunctualRevisionV1`
record type and its encrypted Bytes `payload` field in the existing container's
development schema, then deploy that additive schema to production using CloudKit
Console. Leave existing Core Data types and zones intact. A development build
with a dedicated test account can create the additive schema when it first sends
a revision. No schema-initialization or production mutation was performed by the
automated tests for this change. Until the schema is deployed, cloud writes fail
visibly and the cloud-mode gate remains closed; local values remain available.

Back up the original SQLite store (including WAL/SHM while closed) and the retained
archive before any manual recovery. Do not replace a corrupt archive with an
empty one or reopen the old store with automatic mirroring. Recovery history and
old-account receipts deliberately remain on the device. New-account consent
includes historical/recovery values, not only the visible head. Normal reminder
and tag deletion uses tombstone revisions; no cloud-data-deletion, storage-size,
remote-device-disable, or server-login feature is present.

The archive and cloud history currently retain all revisions, without compaction
or garbage collection. Writes encode the archive atomically; archive size therefore
affects save cost. The production app has one writer process and shares its actor
across scenes. Widget extensions consume their existing separate snapshot file.

## Validation and remaining checks

Automated fixture coverage includes signed-out and disabled persistence, OFF
across restart, unknown identities, refusal, account-scoped receipts, late
acknowledgments with equal timestamps, imported-commit gating, future/corrupt raw
payload preservation, UUID/tag migration, encrypted legacy values/assets and CDMR
relationships, causal deletion conflicts, restore copies, failed local saves,
corrupt-archive refusal, shared-scene serialization and restart receipt
revalidation. No test changes the real Apple Account, removes CloudKit data, or requires production credentials.

Validation on 2026-11-15: the full CI check passed, including strict Swift
format/SwiftLint (zero violations), all 336 English/Japanese localization keys,
localization fixtures, distribution checks/mutation fixtures, Xcode Cloud hook
fixtures and all 382 core package tests (including 18 retained-persistence cases).
ShellCheck passed for both changed distribution scripts. Debug and Release iOS
Simulator builds passed, and all Xcode test targets built successfully.

Xcode unit/integration execution failed before any tests launched: CoreSimulator
reported “Timed out waiting for remote invocation callback; the server may have
crashed.” A separate simulator boot attempt failed with the same timeout. These
are failed execution checks, not passing test runs; the two new settings-model
cases are compiled but have not executed. UI screenshots are unavailable for the
same reason.

Real-device OS permission transitions, Apple Account sign-out/switch while saves
are in flight, two-device merging, production schema deployment and mixed-version
legacy interoperability remain unverified until run with dedicated test accounts.
Manual scheduling depends on app execution: launch/resume, local mutation,
reachability changes, manual retry and permitted CloudKit background notifications
are sync opportunities, not a guarantee of immediate background delivery.

## Official references

- [Apple: Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/)
  describes per-record save results, conflict handling and account changes.
- [Apple: CKSyncEngine configuration](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/configuration)
  documents manual scheduling and serialized engine state.
- [Apple: Reading CloudKit Records for Core Data](https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data)
  specifies the legacy attribute, asset and CDMR relationship representation.
- [Apple: cancelOperations](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/canceloperations())
  notes that in-flight work can complete after cancellation; generation/account
  checks remain necessary.
- [Apple: CloudKit container environments](https://developer.apple.com/documentation/cloudkit/ckcontainer)
  explains that the signed entitlement selects development versus production;
  cached local receipts therefore require validation against the current database.
