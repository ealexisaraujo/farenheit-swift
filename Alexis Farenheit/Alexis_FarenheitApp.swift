//
//  Alexis_FarenheitApp.swift
//  Alexis Farenheit
//
//  Created by Alexis Araujo (CS) on 05/12/25.
//

import SwiftUI
import BackgroundTasks

@main
struct Alexis_FarenheitApp: App {

    // MARK: - Environment
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Init
    init() {
        // Disable file logging during init to prevent blocking
        SharedLogger.shared.fileLoggingEnabled = false

        // Register background tasks early in app lifecycle
        print("🚀 App initializing...")
        BackgroundTaskService.shared.registerBackgroundTasks()

        // Re-enable file logging after init
        SharedLogger.shared.fileLoggingEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    // MARK: - Scene Phase Handling

    /// Handle app lifecycle changes for background task scheduling
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Debug: App going to background
            print("🚀 App going to background - scheduling refresh")
            SharedLogger.shared.info("App moved to background", category: "Lifecycle")
            
            // Flush pending logs before going to background
            SharedLogger.shared.flushPendingLogs()

            // Schedule background refresh when app goes to background
            BackgroundTaskService.shared.scheduleAppRefresh()

        case .active:
            // Debug: App became active
            print("🚀 App became active")

        case .inactive:
            // Debug: App became inactive (transitioning)
            print("🚀 App became inactive")

        @unknown default:
            break
        }
    }
}

