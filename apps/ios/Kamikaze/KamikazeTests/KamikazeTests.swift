//
//  KamikazeTests.swift
//  KamikazeTests
//
//  Created by Daniel Sateler on 12-08-26.
//

import Testing
@testable import Kamikaze

struct KamikazeTests {

    /// Navigation contract. BETA is the temporary experiment bench Daniel
    /// requested for the beta phase (2026-08-15); removing it later restores
    /// the four-tab layout in one place.
    @MainActor
    @Test func appHasTheApprovedTabs() {
        #expect(AppTab.allCases == [.play, .practice, .locker, .beta, .profile])
    }

}
