//
//  KamikazeTests.swift
//  KamikazeTests
//
//  Created by Daniel Sateler on 12-08-26.
//

import Testing
@testable import Kamikaze

struct KamikazeTests {

    @MainActor
    @Test func appHasTheFourApprovedBetaTabs() {
        #expect(AppTab.allCases == [.play, .practice, .locker, .profile])
    }

}
