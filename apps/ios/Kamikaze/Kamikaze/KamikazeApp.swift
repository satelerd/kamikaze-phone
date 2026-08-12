//
//  KamikazeApp.swift
//  Kamikaze
//
//  Created by Daniel Sateler on 12-08-26.
//

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
            ContentView()
        }
    }
}
