//
//  KamikazeApp.swift
//  Kamikaze
//
//  Created by Daniel Sateler on 12-08-26.
//

import ClerkKit
import SwiftUI

@main
struct KamikazeApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") {
            UserDefaults.standard.set(false, forKey: "onboardingComplete")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let clerk = KamikazeIdentityConfiguration.clerk {
                ContentView()
                    .environment(clerk)
                    .task { KamikazeCloudSync.shared.start() }
            } else {
                ContentView()
            }
        }
    }
}
