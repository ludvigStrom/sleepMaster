import AppKit
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class SparkleUpdater {
    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    #endif

    var isConfigured: Bool {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return false }
        return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() {
        guard isConfigured else { return }
        #if canImport(Sparkle)
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }
}

enum SparkleConfiguration {
    static var feedURL: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    static var publicEDKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }
}
