//
//  ContentView.swift
//  EverEra
//
//  Root view: NavigationSplitView with sidebar + detail area.
//  Liquid Glass navigation elements are provided automatically by the system.
//
//  Export/Import archive actions live here because this is the view with
//  access to the SwiftData environment. They are surfaced to the app menu
//  via a FocusedValue so that EverEraCommands can trigger them.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sidebarSelection: SidebarDestination? = .timeline

    // MARK: - Export / Import state

    @Query private var entities: [LSEntity]
    @Environment(\.modelContext) private var modelContext

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDocument: EverEraJSONDocument?
    @State private var exportError: String?
    @State private var importError: String?
    @State private var importSuccess: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.prominentDetail)
        // Wire export/import actions so the Commands menu can trigger them.
        .focusedValue(\.archiveActions, ArchiveActions(
            exportArchive: { triggerExport() },
            importArchive: { showingImporter = true }
        ))
        // Export sheet
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "EverEra-Archive-\(formattedDate()).json"
        ) { result in
            if case .failure(let err) = result {
                exportError = err.localizedDescription
            }
        }
        // Import sheet
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .failure(let err):
                importError = err.localizedDescription
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    try DataExportService.importJSON(data, into: modelContext)
                    importSuccess = "Archive imported successfully."
                } catch {
                    importError = "Import failed: \(error.localizedDescription)"
                }
            }
        }
        .alert("Export Error", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Import Complete", isPresented: .constant(importSuccess != nil)) {
            Button("OK") { importSuccess = nil }
        } message: {
            Text(importSuccess ?? "")
        }
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

    // MARK: - Helpers

    private func triggerExport() {
        do {
            let data = try DataExportService.exportJSON(entities: entities)
            exportDocument = EverEraJSONDocument(data: data)
            showingExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LSEntity.self, LSEvent.self, LSDocument.self, LSProperty.self], inMemory: true)
}
