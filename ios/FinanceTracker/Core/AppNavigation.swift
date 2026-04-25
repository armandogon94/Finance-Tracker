//
//  AppNavigation.swift
//  Tiny @Observable holder for cross-feature navigation signals. Lets a
//  feature view (e.g. ScanView after a save) request that the root tab
//  bar switch tabs, without coupling that view to RootView's @State.
//

import SwiftUI
import Observation

@Observable @MainActor
final class AppNavigation {
    /// The tab the root TabView should be showing. Mirrors RootView's
    /// @State seed but lives outside it so leaf views can mutate it.
    var selectedTab: Tab = .home

    init(initial: Tab = .home) {
        self.selectedTab = initial
    }
}
