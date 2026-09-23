import SwiftUI
import Foundation

@main
struct NextCueApp: App {
    @StateObject private var routines: RoutineStore
    @StateObject private var purchases: StoreService

    init() {
        #if DEBUG
        let shouldReset = Self.resetUITestDataIfRequested()
        #endif
        _routines = StateObject(wrappedValue: RoutineStore.shared)
        let storeService = StoreService.shared
        #if DEBUG
        if shouldReset { storeService.setLocalOverride(isPro: false) }
        #endif
        _purchases = StateObject(wrappedValue: storeService)
    }

    var body: some Scene {
        WindowGroup {
            NextCueRootView()
                .environmentObject(routines)
                .environmentObject(purchases)
        }
    }

    private static func resetUITestDataIfRequested() -> Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let shouldReset = arguments.contains("-ResetUITestData") || arguments.contains("-SeedScreenshotData")
        guard shouldReset else { return false }
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let snapshotURL = supportDirectory
            .appendingPathComponent("NextCue", isDirectory: true)
            .appendingPathComponent("nextcue-state.json")
        try? FileManager.default.removeItem(at: snapshotURL)
        UserDefaults.standard.removeObject(forKey: "nextcue.reviewPromptHandled")
        return true
        #else
        return false
        #endif
    }
}
