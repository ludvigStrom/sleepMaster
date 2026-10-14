import XCTest

@MainActor
final class AssertionSleepControllerTests: XCTestCase {
    func testAssertionAppearsInPmsetWhileHeld() throws {
        let controller = AssertionSleepController()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(pmsetAssertionsContainSleepmaster(), "A leftover Sleepmaster assertion was already listed.")

        try controller.start()
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(
            pmsetAssertionsContainSleepmaster(),
            "pmset -g assertions should list Sleepmaster after start."
        )

        try controller.stop()
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(
            pmsetAssertionsContainSleepmaster(),
            "pmset -g assertions should not list Sleepmaster after stop."
        )
    }

    func testStartWhileActiveIsANoOp() throws {
        let controller = AssertionSleepController()
        try controller.start()
        try controller.start()
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(pmsetAssertionsContainSleepmaster())
        try controller.stop()
    }

    private func pmsetAssertionsContainSleepmaster() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            XCTFail("Could not run pmset: \(error)")
            return false
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("\"Sleepmaster\"")
    }
}
