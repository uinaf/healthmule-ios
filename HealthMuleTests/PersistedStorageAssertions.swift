import Foundation
import XCTest

enum PersistedStorageAssertions {
    static func assertProtectedAndExcludedFromBackup(
        _ url: URL,
        expectedProtection: FileProtectionType =
            .completeUntilFirstUserAuthentication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let values = try url.resourceValues(
            forKeys: [.isExcludedFromBackupKey, .fileProtectionKey]
        )
        XCTAssertEqual(
            values.isExcludedFromBackup,
            true,
            file: file,
            line: line
        )
        if let protection = values.fileProtection {
            let expectedURLProtection = try XCTUnwrap(
                [
                    FileProtectionType.none: URLFileProtection.none,
                    .complete: .complete,
                    .completeUnlessOpen: .completeUnlessOpen,
                    .completeUntilFirstUserAuthentication:
                        .completeUntilFirstUserAuthentication,
                    .completeWhenUserInactive: .completeWhenUserInactive,
                ][expectedProtection],
                "unsupported file protection class",
                file: file,
                line: line
            )
            XCTAssertEqual(
                protection,
                expectedURLProtection,
                file: file,
                line: line
            )
            return
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(
                protection,
                expectedProtection,
                file: file,
                line: line
            )
            return
        }
        XCTFail("missing file protection class", file: file, line: line)
    }
}
