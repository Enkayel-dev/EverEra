//
//  EverEraApp.swift
//  EverEra
//
//  App entry point.  Configures the SwiftData ModelContainer for the full
//  LifeGraph schema: LSEntity → LSEvent → LSDocument.
//
//  Export / Import commands are wired through a @FocusedValue so that the
//  menu items can trigger actions defined inside ContentView, which does
//  have access to the SwiftData environment.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct EverEraApp: App {

    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LSEntity.self,
            LSEvent.self,
            LSDocument.self,
            LSProperty.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            EverEraCommands()
        }
    }
}

// MARK: - FocusedValue key for archive actions

/// Allows the Commands menu to trigger export/import actions
/// defined inside the focused ContentView.
struct ArchiveActionsKey: FocusedValueKey {
    typealias Value = ArchiveActions
}

struct ArchiveActions: Sendable {
    var exportArchive: @Sendable @MainActor () -> Void
    var importArchive: @Sendable @MainActor () -> Void
}

extension FocusedValues {
    var archiveActions: ArchiveActions? {
        get { self[ArchiveActionsKey.self] }
        set { self[ArchiveActionsKey.self] = newValue }
    }
}

// MARK: - EverEraCommands

struct EverEraCommands: Commands {
    @FocusedValue(\.archiveActions) private var archiveActions

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()

            Button("Export Archive…") {
                archiveActions?.exportArchive()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(archiveActions == nil)

            Button("Import Archive…") {
                archiveActions?.importArchive()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(archiveActions == nil)
        }
    }
}
