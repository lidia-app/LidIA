import Foundation
import Sparkle

@MainActor
@Observable
final class UpdateController {
    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates = false
    var lastUpdateCheckDate: Date?

    init() {
        // Don't auto-start until real EdDSA keys are configured in Info.plist
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }
}
