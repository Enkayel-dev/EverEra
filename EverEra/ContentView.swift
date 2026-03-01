//
//  ContentView.swift
//  EverEra
//
//  Root view: NavigationSplitView with sidebar + detail area.
//  Liquid Glass navigation elements are provided automatically by the system.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var sidebarSelection: SidebarDestination? = .timeline

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    @ViewBuilder
    private var detailView: some View {
        switch sidebarSelection {
        case .timeline, .none:
            TimelineMainView()
        case .entityHub:
            EntityHubView()
        case .documents:
            DocumentCenterView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LSEntity.self, LSEvent.self, LSDocument.self, LSProperty.self], inMemory: true)
}
