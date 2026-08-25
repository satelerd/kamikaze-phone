//
//  KamikazeTests.swift
//  KamikazeTests
//
//  Created by Daniel Sateler on 12-08-26.
//

import Testing
@testable import Kamikaze

struct KamikazeTests {

    /// Navigation contract. BETA is the temporary experiment bench and stays
    /// at the far-right edge, after the player-facing ME destination.
    @MainActor
    @Test func appHasTheApprovedTabs() {
        #expect(AppTab.allCases == [.play, .practice, .locker, .profile, .feed])
    }

}
