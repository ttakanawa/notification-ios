# Live Activity delivery and customization

This app change depends on [retained iCloud persistence PR #9](https://github.com/ttakanawa/notification-ios/pull/9) and [the Rust service PR #1](https://github.com/ttakanawa/punctual-live-activity-server/pull/1). Neither PR is merged or deployed by this work. The app integration PR targets the iCloud branch so its diff stays separate; merge the iCloud PR first, then retarget the integration PR to main.

## Data flow

  ```mermaid
  flowchart TD
    Edit[Edit a reminder] --> Local[Durable local revision]
    Local --> Gate{Cloud sync enabled?}
    Gate -->|Yes| Cloud[CloudKit exact revision acknowledgment]
    Gate -->|No| Ready[Eligible local snapshot]
    Cloud --> Ready
    Ready --> Activity[This device's ActivityKit activity and push token]
    Activity --> Queue[Persistent local API outbox]
    Queue --> Attest[App Attest signed API request]
    Attest --> DO[SQLite Durable Object and Alarm]
    DO -->|Due time| APNs[APNs end event]
    APNs --> End[This device's Live Activity ends]
    Close[Free close button] --> Suppress[Suppress this occurrence on this device]
    Suppress --> Cancel[Durable server cancellation]
    Suppress --> End
  ```

Each installation owns separate job UUIDs, revision counters and ActivityKit tokens. None of these synchronize through iCloud. A second device observes the shared reminder through CloudKit, then independently updates its own Activity and job. There is no backend Apple Account identity or server-side fan-out.

[The remote coordinator](../NotificationManager/DeviceServices/LiveActivities/ReminderLiveActivityRemoteCoordinator.swift) revalidates the latest reminder against [the exact commit gate](../Packages/NotificationManagerCore/Sources/NotificationManagerApplication/Ports/ReminderCloudCommitChecking.swift). An offline schedule edit stays in the local archive. With cloud sync enabled, its timing PUT cannot leave until the corresponding current cloud revision is acknowledged. Account uncertainty closes the gate. Cloud changes and network recovery trigger another reconciliation when iOS gives the app execution time.

[The outbox](../Packages/NotificationManagerCore/Sources/NotificationManagerWidgetSupport/LiveActivityEndOutbox.swift) persists job UUIDs, unsigned raw request bytes and monotonically increasing revisions before sending. Authentication assertions are generated fresh for each transmission. Restart requires a fresh reminder/gate validation before a restored timing PUT can leave. Uncommitted schedule edits do not prevent a token-only PATCH for an existing job. Local closure and cancellation do not wait for cloud upload. A failed local write cannot authorize an unpersisted or obsolete PUT.

A stale/conflicting revision triggers fresh reconciliation. Once dispatch started, timing PUTs stop for that job; token PATCH and cancellation remain available. Terminal jobs do not reopen. The service can already have handed a request to APNs when cancellation arrives, so cancellation cannot recall an accepted/in-flight push.

## API contract

The canonical detailed request/response schemas, authentication signing rules, revision semantics, errors and limits are maintained in [API v1](https://github.com/ttakanawa/punctual-live-activity-server/blob/rust-end-api/docs/api-v1.md) and [OpenAPI](https://github.com/ttakanawa/punctual-live-activity-server/blob/rust-end-api/contracts/openapi.json).

| Operation | Endpoint | Main input |
| --------- | -------- | ---------- |
| Issue a nonce | POST /v1/auth/challenges | purpose, keyId |
| Register an installation | POST /v1/auth/attestations | keyId, challengeId, attestationObject |
| Create/update an end job | PUT /v1/end-jobs/{jobId} | revision, pushToken, startsAt, notificationAt, endsAt, activityEndsAt, contentStateVersion |
| Replace a token | PATCH /v1/end-jobs/{jobId}/push-token | revision, pushToken |
| Cancel | DELETE /v1/end-jobs/{jobId} | revision |
| Inspect own job | GET /v1/end-jobs/{jobId} | Empty body |

Revisions are decimal UInt64 strings. Times are whole-second UTC ISO 8601 strings. Business responses include jobId, revision, status, activityEndsAt and delivery state/count/acceptance evidence. Errors have error.code, requestId and, for revision conflicts, error.details.currentRevision. Other installations cannot inspect or change a job.

The three business authentication headers are X-App-Attest-Key-Id, X-App-Attest-Challenge-Id and X-App-Attest-Assertion. The assertion covers deployment environment, key, nonce ID/value, HTTP method, exact path and SHA-256 of the raw body with the contract's trailing newline. Requests contain no reminder title, notes, template, iCloud identity or StoreKit purchase data. The shared signing, revision-error and end-state fixtures are copied into [the Swift tests](../Packages/NotificationManagerCore/Tests/NotificationManagerWidgetSupportTests/Fixtures).

## Free close button

[The close intent](../Packages/NotificationManagerCore/Sources/NotificationManagerWidgetSupport/DismissReminderLiveActivityIntent.swift) appears on the Lock Screen and expanded Dynamic Island. It ends all local Activities for this occurrence immediately, stores suppression separately from the running service's cached state, and queues server cancellation. It is available without a purchase and does not open an app screen. It never cancels the ordinary notification or future occurrences. Offline cancellation retries when the app next receives execution time; iOS background execution is not guaranteed.

## Purchase and templates

[The StoreKit model](../NotificationManager/Features/Customization/DisplayCustomizationPurchaseModel.swift) verifies StoreKit 2 non-consumable transactions and current entitlements locally. A verified purchase unlocks both surfaces. Pending approval does not unlock; cancellation does not show a failure. Restore is an explicit user action. Refund/revocation refreshes appearance when observed by the app without erasing synced templates. No purchase Boolean is trusted from UserDefaults or iCloud. Product name and price come from StoreKit.

Settings provides global defaults. A saved reminder has its own editor; save a new reminder before setting its override. Each surface independently inherits its global default when its override is off. A global surface that is off uses the built-in display. The individual editor saves separately from ordinary reminder edits, and the UI explains this. A device without entitlement retains the data but renders the built-in appearance.

The editor offers field insertion, presets and free-form title/body templates. Supported fields are {title}, {notes}, {notificationTime} and {timeZone}. Only Live Activities accept {remaining} and {elapsed}; they are archived native system timers rather than app-run ticking tasks. Doubled braces {{ and }} produce literal braces. Unknown fields, malformed braces, empty resolved titles and excessive payload sizes fall back to standard appearance. Ordinary notification text keeps existing UTF-8 truncation limits. Live Activity custom data reserves room within the ActivityKit payload limit. Compact/minimal Dynamic Island still uses the app icon and compact counters; the custom title/body applies to expanded and Lock Screen content.

[The template renderer](../Packages/NotificationManagerCore/Sources/NotificationManagerWidgetSupport/DisplayTemplateRenderer.swift) treats inserted values as literal text and never evaluates code. Unsupported/corrupt customization data is read-only until explicit replacement confirmation. Other reminder edits preserve its original bytes.

## Owner setup: GitHub and Cloudflare

All backend registration values go in **ttakanawa/punctual-live-activity-server**, not the iOS repository. Full permissions and deployment instructions are in [the server deployment guide](https://github.com/ttakanawa/punctual-live-activity-server/blob/rust-end-api/docs/deployment.md).

| GitHub scope | Kind | Name | Value |
| ------------ | ---- | ---- | ----- |
| Repository | Secret | CLOUDFLARE_API_TOKEN | Account-scoped Workers deployment token |
| Repository | Variable | CLOUDFLARE_ACCOUNT_ID | Intended Cloudflare account ID |
| Environments development and production, independently | Secret | APNS_PRIVATE_KEY | Entire APNs .p8 PEM, including newlines |
| Each environment | Variable | APNS_KEY_ID | APNs key ID |
| Each environment | Variable | APPLE_TEAM_ID | Apple Developer team ID |
| Each environment | Variable | APPLE_APP_ID_PREFIX | Registered App ID prefix; verify it rather than assuming the team ID |
| Each environment | Variable | APP_ATTEST_ENVIRONMENT | development or production for the signed Apple entitlement |
| Each environment | Variable | APNS_ENVIRONMENT | sandbox or production for that build's Activity token |
| Each environment | Optional variable | ATTEST_ALLOWED_CATEGORIES | Apple validation categories; server defaults are documented |
| Each environment | Optional variable | ATTEST_ALLOWED_BUNDLE_VERSIONS | Approved CFBundleVersion list, or empty |

Create the two GitHub Environments with those exact names. Enable owner review for production. The Cloudflare account needs Workers Paid and a workers.dev subdomain. Wrangler creates the Worker and SQLite Durable Object namespaces; there is no external Workers KV or SQL database service. Deployment is manual after review. The initial workflow becomes runnable in Actions after the server PR reaches its default branch.

Never put keys in a PR, source, command-line argument, log or chat. The iOS app needs no APNs signing private key, Cloudflare token, shared API secret, App Store server key or GitHub purchase secret.

## Owner setup: app and Apple

1. Enable App Attest and Push Notifications for the existing explicit App ID org.tknw.punctual. Regenerate development/distribution profiles. Keep the existing App Group and CloudKit container. Test App Attest and remote endings on supported physical devices.
2. After server deployment, set the public HTTPS origin in PUNCTUAL_END_API_ORIGIN for the app target's Debug/Release build settings in [the project](../NotificationManager.xcodeproj/project.pbxproj). No path/query or credentials are allowed. The checked-in empty origin intentionally disables remote transmission until configured. An unset origin still allows local Activities and the close button, but cannot provide server endings. Set this before a release that advertises remote endings.
3. Keep PUNCTUAL_END_API_ENVIRONMENT equal to the service deployment name in the signing contract. PUNCTUAL_APP_ATTEST_ENVIRONMENT controls Apple's entitlement and the credential namespace. Defaults are development/development for Debug and production/production for Release. TestFlight requires production App Attest and APNs; a staging service serving TestFlight must also be configured for those Apple environments, while its API signing environment can remain development. Origin, service environment and Apple attestation environment isolate credential/outbox files.
4. In App Store Connect → Punctual → In-App Purchases, create **Non-Consumable**, product ID **org.tknw.punctual.display_customization**. Supply localized name/description, selected price, availability and review screenshot. Complete applicable paid-app agreements/tax/banking setup and submit the product with the app as required. This work does not set a sales price or enable Family Sharing.
5. For local purchase testing, create/select an Xcode StoreKit configuration for that exact product ID, or use a sandbox tester. Test purchase, pending approval, cancellation, restore and revocation. A StoreKit configuration file is a test tool; never replace verified production entitlements with an app preference.
6. Deploy the additive encrypted CloudKit schema described in [the iCloud rollout guide](icloud-retained-persistence.md). Upgrade all devices for two-way editing: old clients do not receive upgraded writes. Existing legacy cloud records and the original local mirror are retained.
7. Update App Store Connect App Privacy and the published privacy policy to match the real end service. [The privacy manifest](../NotificationManager/Resources/PrivacyInfo.xcprivacy) declares device identifiers, other user content (timing) and other security data, linked to the installation solely for app functionality, without tracking. No title, note, template or Apple Account identity goes to the server. Confirm Cloudflare retention/logging and platform backup settings. This classification is conservative for the implemented payload, not a claim that an anonymous installation ID is non-identifying. See [Apple's collection definitions](https://developer.apple.com/app-store/app-privacy-details/) and [privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests).

## Verification and remaining device checks

Automated evidence is recorded in the integration PR. Package tests cover signing fixtures, raw replay, local write failures, cloud gating, stale revisions, token rotation, in-flight cancellation, retry wake-ups, template parsing/timer restrictions and size bounds. Xcode builds compile the StoreKit/editor/service/ordering tests. The exact production purchase/editor model sources also passed nine tests in a temporary macOS SwiftPM harness, changing only the test module import. That harness uses mocked StoreKit outcomes and does not validate sandbox purchases or SwiftUI. Simulator test execution in this environment fails before launch with CoreSimulator's remote-invocation callback timeout; compiled tests are not reported as executed.

With dedicated test accounts/devices, verify system and in-app iCloud OFF, offline edits/reconnect, restart, same/different account confirmation/refusal, two-device edits and legacy migration. Verify that no new timing PUT arrives before the exact cloud acknowledgment. Verify physical Activity tokens, App Attest assertions, end receipt on Lock Screen and Dynamic Island, cancellation while offline/in-flight, token changes and windows capped at eight hours. Exercise free closure without purchasing and confirm ordinary notifications and later occurrences still fire. Test unpaid/paid/revoked devices with synced settings and accessibility in Japanese/English.

Alarm execution, APNs acceptance and device presentation are separate stages. Network loss, OS scheduling and missing Activity tokens prevent an exact-time guarantee. A suspended or terminated app may not receive a new token or cloud update until iOS grants execution. Never describe an APNs HTTP 200 or a passing local test as proof that a device dismissed its Activity. Credentials, deployment, production CloudKit changes and live device validation remain owner steps.
