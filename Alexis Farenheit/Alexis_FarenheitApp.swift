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
        // Register background tasks early in app lifecycle
        // Debug: App initializing
        print("🚀 App initializing...")
        BackgroundTaskService.shared.registerBackgroundTasks()
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

            // Schedule background refresh when app goes to background
            BackgroundTaskService.shared.scheduleAppRefresh()

        case .active:
            // Debug: App became active
            print("🚀 App became active")
            SharedLogger.shared.info("App became active", category: "Lifecycle")

        case .inactive:
            // Debug: App became inactive (transitioning)
            print("🚀 App became inactive")

        @unknown default:
            break
        }
    }
}

