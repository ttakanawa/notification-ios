import Foundation
import Testing

@testable import NotificationManagerDomain

@Suite("Notifications.NotificationIdentifierCodec")
struct NotificationIdentifierCodecTests {
    @Test func reproducesNormativeRepeatingDocumentDigestAndIdentifier() throws {
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            weekday: 2,
            hour: 9,
            minute: 30,
            second: 0
        )

        #expect(
            try components.canonicalDocument()
                == Data(
                    #"{"calendar":"gregorian","hour":9,"minute":30,"repeats":true,"second":0,"timeZone":"America/New_York","weekday":2}"#
                        .utf8
                ))
        #expect(
            try codec.repeatingDigest(components: components)
                == "04fcbfbe9200234ade132aff6e19d6c9cc7e4ee07c8d0fc4505c6f622a1750af")
        let expectedIdentifier =
            "notification-manager.local.v1.r.123e4567-e89b-12d3-a456-426614174000."
            + "04fcbfbe9200234ade132aff6e19d6c9cc7e4ee07c8d0fc4505c6f622a1750af"
        #expect(
            try codec.repeatingIdentifier(
                reminderID: UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!,
                components: components
            ) == expectedIdentifier
        )
    }

    @Test func nonzeroSecondContributesToCanonicalDocumentAndDigest() throws {
        let components = RepeatingTriggerComponents(
            timeZoneIdentifier: "America/New_York",
            hour: 9,
            minute: 29,
            second: 30
        )

        #expect(
            try components.canonicalDocument()
                == Data(
                    #"{"calendar":"gregorian","hour":9,"minute":29,"repeats":true,"second":30,"timeZone":"America/New_York"}"#
                        .utf8
                ))
        #expect(
            try codec.repeatingDigest(components: components)
                == "1c12c766831bcf6e4ebc7366f2a03dfbe06fff19cb1c87735f6cf8a6eef2e552"
        )
    }

    @Test func canonicalDocumentsContainOnlyPresentFieldsInSortedOrder() throws {
        let fixtures: [(RepeatingTriggerComponents, String)] = [
            (
                .init(timeZoneIdentifier: "UTC", hour: 7, minute: 5, second: 0),
                #"{"calendar":"gregorian","hour":7,"minute":5,"repeats":true,"second":0,"timeZone":"UTC"}"#
            ),
            (
                .init(timeZoneIdentifier: "Asia/Manila", day: 31, hour: 23, minute: 59, second: 0),
                #"{"calendar":"gregorian","day":31,"hour":23,"minute":59,"repeats":true,"second":0,"timeZone":"Asia/Manila"}"#
            ),
            (
                .init(
                    timeZoneIdentifier: "Asia/Tokyo", month: 2, day: 29, hour: 0, minute: 0,
                    second: 0),
                #"{"calendar":"gregorian","day":29,"hour":0,"minute":0,"month":2,"repeats":true,"second":0,"timeZone":"Asia/Tokyo"}"#
            )
        ]

        for (components, expected) in fixtures {
            #expect(try components.canonicalDocument() == Data(expected.utf8))
        }
    }

    @Test func rejectsComponentsThatCannotBeExactGregorianRepeatingTriggers() {
        let invalid = [
            RepeatingTriggerComponents(
                timeZoneIdentifier: "Not/A_Zone", hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 0, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", day: 32, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", weekday: 0, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(timeZoneIdentifier: "UTC", hour: 24, minute: 0, second: 0),
            RepeatingTriggerComponents(timeZoneIdentifier: "UTC", hour: 9, minute: 60, second: 0),
            RepeatingTriggerComponents(timeZoneIdentifier: "UTC", hour: 9, minute: 0, second: -1),
            RepeatingTriggerComponents(timeZoneIdentifier: "UTC", hour: 9, minute: 0, second: 60)
        ]

        for components in invalid {
            #expect(throws: NotificationIdentifierCodecError.invalidRepeatingComponents) {
                _ = try components.canonicalDocument()
            }
        }
    }

    @Test func rejectsImpossibleMixedAndPartialTriggerShapes() {
        let invalid = [
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 2, day: 30, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 4, day: 31, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 2, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 2, weekday: 2, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", day: 15, weekday: 2, hour: 9, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 2, day: 29, weekday: 2, hour: 9, minute: 0,
                second: 0)
        ]

        for components in invalid {
            #expect(throws: NotificationIdentifierCodecError.invalidRepeatingComponents) {
                _ = try components.canonicalDocument()
            }
            #expect(throws: NotificationIdentifierCodecError.invalidRepeatingComponents) {
                _ = try codec.repeatingIdentifier(
                    reminderID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    components: components
                )
            }
        }
    }

    @Test func acceptsEveryAllowedTriggerShapeAtItsBoundaries() throws {
        let allowed = [
            RepeatingTriggerComponents(timeZoneIdentifier: "UTC", hour: 0, minute: 0, second: 0),
            RepeatingTriggerComponents(timeZoneIdentifier: "UTC", hour: 23, minute: 59, second: 59),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", weekday: 7, hour: 23, minute: 59, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", day: 31, hour: 23, minute: 59, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 2, day: 29, hour: 0, minute: 0, second: 0),
            RepeatingTriggerComponents(
                timeZoneIdentifier: "UTC", month: 12, day: 31, hour: 23, minute: 59, second: 0)
        ]

        for components in allowed {
            #expect(try !components.canonicalDocument().isEmpty)
        }
    }

    @Test func oneShotIdentifiersUseCanonicalSignedIntegralInt64UnixSeconds() throws {
        let reminderID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let fixtures: [(Date, String)] = [
            (Date(timeIntervalSince1970: -9_223_372_036_854_775_808), "-9223372036854775808"),
            (Date(timeIntervalSince1970: -1), "-1"),
            (Date(timeIntervalSince1970: 0), "0"),
            (Date(timeIntervalSince1970: 1), "1"),
            (Date(timeIntervalSince1970: 9_223_372_036_854_774_784), "9223372036854774784")
        ]

        for (instant, suffix) in fixtures {
            #expect(
                try codec.oneShotIdentifier(reminderID: reminderID, alertInstant: instant)
                    == "notification-manager.local.v1.o.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.\(suffix)"
            )
        }
    }

    @Test func oneShotIdentifiersRejectFractionalNonfiniteAndOutOfRangeDates() {
        let reminderID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let invalid = [
            Date(timeIntervalSince1970: 0.5),
            Date(timeIntervalSince1970: .infinity),
            Date(timeIntervalSince1970: -.infinity),
            Date(timeIntervalSince1970: .nan),
            Date(timeIntervalSince1970: 9_223_372_036_854_775_808)
        ]

        for instant in invalid {
            #expect(throws: NotificationIdentifierCodecError.invalidAlertInstant) {
                _ = try codec.oneShotIdentifier(reminderID: reminderID, alertInstant: instant)
            }
        }
    }

    @Test func classifiesOnlyExactCurrentGrammarAndCanonicalSuffixes() {
        let uuid = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
        let digest = String(repeating: "a", count: 64)

        #expect(
            codec.classify(
                "notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.-9223372036854775808"
            )
                == .currentOneShot(reminderID: uuid, unixSeconds: .min))
        #expect(
            codec.classify(
                "notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.9223372036854775807"
            )
                == .currentOneShot(reminderID: uuid, unixSeconds: .max))
        #expect(
            codec.classify(
                "notification-manager.local.v1.r.123e4567-e89b-12d3-a456-426614174000.\(digest)")
                == .currentRepeating(reminderID: uuid, digest: digest))

        let stale = [
            "notification-manager.local.",
            "notification-manager.local.v2.o.123e4567-e89b-12d3-a456-426614174000.0",
            "notification-manager.local.v1.x.123e4567-e89b-12d3-a456-426614174000.0",
            "notification-manager.local.v1.o.123E4567-E89B-12D3-A456-426614174000.0",
            "notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.+1",
            "notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.01",
            "notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.-0",
            "notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.9223372036854775808",
            "notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.0.trailing",
            "notification-manager.local.v1.r.123e4567-e89b-12d3-a456-426614174000.\(String(repeating: "A", count: 64))",
            "notification-manager.local.v1.r.123e4567-e89b-12d3-a456-426614174000.\(String(repeating: "a", count: 63))",
            "notification-manager.local.v1.r.123e4567-e89b-12d3-a456-426614174000.\(String(repeating: "g", count: 64))",
            "notification-manager.local.v1.r.123e4567-e89b-12d3-a456-426614174000.\(digest).trailing"
        ]
        for rawValue in stale {
            #expect(codec.classify(rawValue) == .appOwnedStale)
        }

        #expect(
            codec.classify(
                "notification-manager.locals.v1.o.123e4567-e89b-12d3-a456-426614174000.0")
                == .unrelated)
        #expect(
            codec.classify(
                "other.notification-manager.local.v1.o.123e4567-e89b-12d3-a456-426614174000.0")
                == .unrelated)
    }

    private let codec = NotificationIdentifierCodec()
}
