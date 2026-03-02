//
//  SidebarView.swift
//  EverEra
//
//  Primary navigation sidebar.  Drives the detail column via a selection binding.
//

import SwiftUI
import SwiftData

// MARK: - SidebarDestination

enum SidebarDestination: Hashable, CaseIterable {
    case timeline
    case entityHub
    case documents

    var label: String {
        switch self {
        case .timeline:    return "Timeline"
        case .entityHub:   return "Entity Hub"
        case .documents:   return "Documents"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline:    return "timeline.selection"
        case .entityHub:   return "square.grid.2x2.fill"
        case .documents:   return "doc.on.doc.fill"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selection: SidebarDestination?

    // Entity counts for badges
    @Query private var entities: [LSEntity]
    @Query private var documents: [LSDocument]

    var body: some View {
        List(SidebarDestination.allCases, id: \.self, selection: $selection) { destination in
            sidebarRow(for: destination)
        }
        .navigationTitle("EverEra")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    @ViewBuilder
    private func sidebarRow(for destination: SidebarDestination) -> some View {
        switch destination {
        case .entityHub where !entities.isEmpty:
            Label(destination.label, systemImage: destination.systemImage)
                .badge(entities.count)
                .accessibilityLabel("\(destination.label), \(entities.count) entities")
        case .documents where !documents.isEmpty:
            Label(destination.label, systemImage: destination.systemImage)
                .badge(documents.count)
                .accessibilityLabel("\(destination.label), \(documents.count) documents")
        default:
            Label(destination.label, systemImage: destination.systemImage)
        }
    }
}
