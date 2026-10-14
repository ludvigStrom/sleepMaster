import Foundation
import Security

enum CodeIdentity {
    static let appBundleID = "com.ludvigstrom.sleepmaster"
    static let helperBundleID = "com.ludvigstrom.sleepmaster.helper"
    static let machServiceName = "com.ludvigstrom.sleepmaster.helper"
    static let daemonPlistName = "com.ludvigstrom.sleepmaster.helper.plist"

    static func matches(
        bundleID: String?,
        teamID: String?,
        expectedBundleID: String,
        expectedTeamID: String
    ) -> Bool {
        guard let bundleID, let teamID else { return false }
        return bundleID == expectedBundleID && teamID == expectedTeamID && !expectedTeamID.isEmpty
    }

    static func isAuthorizedSleepmaster(pid: pid_t, teamID expectedTeamID: String) -> Bool {
        guard let code = code(forPID: pid) else { return false }
        return matches(
            bundleID: bundleID(for: code),
            teamID: teamID(for: code),
            expectedBundleID: appBundleID,
            expectedTeamID: expectedTeamID
        )
    }

    static func selfTeamID() -> String? {
        guard let code = selfCode() else { return nil }
        return teamID(for: code)
    }

    static func code(forPID pid: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess else { return nil }
        return code
    }

    static func selfCode() -> SecCode? {
        var code: SecCode?
        let status = SecCodeCopySelf([], &code)
        guard status == errSecSuccess else { return nil }
        return code
    }

    static func teamID(for code: SecCode) -> String? {
        signingInfo(for: code)[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func bundleID(for code: SecCode) -> String? {
        let info = signingInfo(for: code)
        if let identifier = info[kSecCodeInfoIdentifier as String] as? String {
            return identifier
        }
        return nil
    }

    private static func signingInfo(for code: SecCode) -> [String: Any] {
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else { return [:] }

        var cfInfo: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &cfInfo)
        guard status == errSecSuccess, let cfInfo else { return [:] }
        return cfInfo as! [String: Any]
    }
}
