import XCTest

final class CodeIdentityTests: XCTestCase {
    func testAcceptsSleepmasterTeamAndBundle() {
        XCTAssertTrue(
            CodeIdentity.matches(
                bundleID: CodeIdentity.appBundleID,
                teamID: "ABCD123456",
                expectedBundleID: CodeIdentity.appBundleID,
                expectedTeamID: "ABCD123456"
            )
        )
    }

    func testRejectsDifferentBundleID() {
        XCTAssertFalse(
            CodeIdentity.matches(
                bundleID: "com.example.other",
                teamID: "ABCD123456",
                expectedBundleID: CodeIdentity.appBundleID,
                expectedTeamID: "ABCD123456"
            )
        )
    }

    func testRejectsDifferentTeamID() {
        XCTAssertFalse(
            CodeIdentity.matches(
                bundleID: CodeIdentity.appBundleID,
                teamID: "OTHERTEAM1",
                expectedBundleID: CodeIdentity.appBundleID,
                expectedTeamID: "ABCD123456"
            )
        )
    }

    func testRejectsMissingIdentity() {
        XCTAssertFalse(
            CodeIdentity.matches(
                bundleID: nil,
                teamID: "ABCD123456",
                expectedBundleID: CodeIdentity.appBundleID,
                expectedTeamID: "ABCD123456"
            )
        )
        XCTAssertFalse(
            CodeIdentity.matches(
                bundleID: CodeIdentity.appBundleID,
                teamID: nil,
                expectedBundleID: CodeIdentity.appBundleID,
                expectedTeamID: "ABCD123456"
            )
        )
        XCTAssertFalse(
            CodeIdentity.matches(
                bundleID: CodeIdentity.appBundleID,
                teamID: "ABCD123456",
                expectedBundleID: CodeIdentity.appBundleID,
                expectedTeamID: ""
            )
        )
    }
}
