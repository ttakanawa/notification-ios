import Foundation
import NotificationManagerDomain
import Testing

@testable import NotificationManagerApplication

@Suite struct TagNameNormalizerTests {
    private let normalizer = TagNameNormalizerV1()

    @Test func appliesUnicode151NFKCCasefoldAcrossRepresentativeOfficialMappings() throws {
        let vectors: [(input: String, expected: String)] = [
            ("  ＴｅＳＴ  ", "test"),
            ("Straße", "strasse"),
            ("Σςσ", "σσσ"),
            ("①Ⅳﬃ", "1ivffi"),
            ("KÅ", "kå"),
            ("İIı", "i\u{0307}iı"),
            ("\u{1D400}\u{10400}", "a\u{10428}"),
            ("A\u{00AD}\u{200D}B", "ab")
        ]

        for vector in vectors {
            #expect(try normalizer.normalize(vector.input) == vector.expected)
        }
    }

    @Test func performsExactWholeStringNFCCompositionAndCanonicalReordering() throws {
        let vectors: [(input: String, expected: String)] = [
            ("A\u{030A}", "å"),
            ("A\u{0315}\u{0300}", "à\u{0315}"),
            ("\u{0344}", "\u{0308}\u{0301}"),
            ("\u{1100}\u{1161}\u{11A8}", "각"),
            ("가\u{11A8}", "각")
        ]

        for vector in vectors {
            #expect(try normalizer.normalize(vector.input) == vector.expected)
        }
    }

    @Test func trimsEveryUnicode151WhiteSpaceScalarAtBothEnds() throws {
        let whiteSpace: [UInt32] = [
            0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x0085, 0x00A0,
            0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
            0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
            0x3000
        ]

        for value in whiteSpace {
            let scalar = try #require(UnicodeScalar(value))
            #expect(try normalizer.normalize("\(scalar)X\(scalar)") == "x")
        }
    }

    @Test func preservesEmbeddedWhitespaceWithoutCollapsingIt() throws {
        #expect(try normalizer.normalize(" A\tB ") == "a\tb")
        #expect(try normalizer.normalize("A\u{2003}\u{2003}B") == "a  b")
    }

    @Test func doesNotTrimScalarsOutsideUnicode151WhiteSpace() throws {
        #expect(try normalizer.normalize("\u{001C}X\u{001F}") == "\u{001C}x\u{001F}")
        #expect(try normalizer.normalize("·X·") == "·x·")
    }

    @Test func usesUnicode151IdentityForLaterAssignedAndUnassignedScalars() throws {
        // U+10D50 became GARAY CAPITAL LETTER A with a fold mapping only in Unicode 16.0.
        #expect(try normalizer.normalize("\u{10D50}") == "\u{10D50}")
        #expect(try normalizer.normalize("\u{0378}") == "\u{0378}")
    }

    @Test func rejectsEmptyNormalizedNames() {
        #expect(throws: TagValidationIssue.normalizedNameEmpty) {
            _ = try normalizer.normalize("\u{2003}\u{00A0}")
        }
        #expect(throws: TagValidationIssue.normalizedNameEmpty) {
            _ = try normalizer.normalize("\u{00AD}\u{200D}")
        }
    }

    @Test func enforcesInputAndNormalizedUTF8ByteLimitsIndependently() throws {
        #expect(try normalizer.normalize(String(repeating: "ß", count: 128)).utf8.count == 256)

        #expect(throws: TagValidationIssue.nameTooLarge) {
            _ = try normalizer.normalize(String(repeating: "a", count: 257))
        }
        #expect(throws: TagValidationIssue.nameTooLarge) {
            _ = try normalizer.normalize(String(repeating: " ", count: 257))
        }
        #expect(throws: TagValidationIssue.normalizedNameTooLarge) {
            _ = try normalizer.normalize(String(repeating: "\u{FDFA}", count: 8))
        }
    }
}
