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
        XCTAssertEqual(sleepmasterAssertionTypes(), ["PreventUserIdleDisplaySleep"])

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

    func testSwapWhileHeldChangesTypeWithoutDroppingAssertion() throws {
        let controller = AssertionSleepController()
        try controller.start()
        XCTAssertEqual(sleepmasterAssertionTypes(), ["PreventUserIdleDisplaySleep"])

        try controller.setAllowDisplaySleep(true)
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(pmsetAssertionsContainSleepmaster())
        XCTAssertEqual(sleepmasterAssertionTypes(), ["PreventUserIdleSystemSleep"])

        try controller.setAllowDisplaySleep(false)
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(pmsetAssertionsContainSleepmaster())
        XCTAssertEqual(sleepmasterAssertionTypes(), ["PreventUserIdleDisplaySleep"])

        try controller.stop()
    }

    func testSetTypeWhileInactiveIsStoredForNextStart() throws {
        let controller = AssertionSleepController()
        try controller.setAllowDisplaySleep(true)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(pmsetAssertionsContainSleepmaster())

        try controller.start()
        XCTAssertEqual(sleepmasterAssertionTypes(), ["PreventUserIdleSystemSleep"])
        try controller.stop()
    }

    private func pmsetAssertionsContainSleepmaster() -> Bool {
        !sleepmasterAssertionLines().isEmpty
    }

    private func sleepmasterAssertionTypes() -> [String] {
        sleepmasterAssertionLines().compactMap { line in
            if line.contains("PreventUserIdleDisplaySleep") {
                return "PreventUserIdleDisplaySleep"
            }
            if line.contains("PreventUserIdleSystemSleep") {
                return "PreventUserIdleSystemSleep"
            }
            return nil
        }
    }

    private func sleepmasterAssertionLines() -> [String] {
        pmsetAssertionOutput()
            .components(separatedBy: .newlines)
            .filter { $0.contains("\"Sleepmaster\"") }
    }

    private func pmsetAssertionOutput() -> String {
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
            return ""
        }

        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
