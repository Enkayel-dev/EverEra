//
//  DocumentCenterView.swift
//  EverEra
//
//  Unified view of all LSDocument assets with full-text search and import.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct DocumentCenterView: View {
    @Query(sort: \LSDocument.importedAt, order: .reverse) private var documents: [LSDocument]
    @Query(sort: \LSEvent.title, order: .forward) private var allEvents: [LSEvent]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var kindFilter: DocumentKind? = nil
    @State private var selectedDocument: LSDocument?
    @State private var showingFileImporter = false
    @State private var pendingImportURLs: [URL] = []
    @State private var showingEventPicker = false
    @State private var importError: String?

    private var filtered: [LSDocument] {
        documents.filter { doc in
            let matchesKind = kindFilter == nil || doc.kind == kindFilter
            let matchesSearch = searchText.isEmpty
                || doc.displayName.localizedCaseInsensitiveContains(searchText)
                || doc.ocrContent.localizedCaseInsensitiveContains(searchText)
                || doc.inferredSummary.localizedCaseInsensitiveContains(searchText)
            return matchesKind && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            kindFilterBar
            Divider()

            if filtered.isEmpty {
                emptyState
            } else {
                documentList
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import Document", systemImage: "square.and.arrow.down")
                }
                .help("Import a document and attach it to an event")
            }
        }
        .searchable(text: $searchText, prompt: "Search documents & content")
        .sheet(item: $selectedDocument) { doc in
            DocumentInspectorView(document: doc, onDelete: {
                modelContext.delete(doc)
                selectedDocument = nil
            })
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .png, .jpeg, .heic],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .failure(let error):
                importError = error.localizedDescription
            case .success(let urls):
                pendingImportURLs = urls
                showingEventPicker = true
            }
        }
        .sheet(isPresented: $showingEventPicker) {
            EventPickerSheet(events: allEvents) { event in
                attachPendingFiles(to: event)
            }
        }
        .alert("Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Kind filter bar

    private var kindFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    FilterChipButton(label: "All", isSelected: kindFilter == nil) {
                        kindFilter = nil
                    }
                    ForEach(DocumentKind.allCases, id: \.self) { kind in
                        FilterChipButton(
                            label: kind.rawValue,
                            systemImage: kind.systemImage,
                            isSelected: kindFilter == kind
                        ) {
                            kindFilter = (kindFilter == kind) ? nil : kind
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: Document list

    private var documentList: some View {
        List(filtered, selection: $selectedDocument) { doc in
            DocumentRowView(document: doc)
                .tag(doc)
        }
        .listStyle(.inset)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No documents imported yet." : "No results for \"\(searchText)\".")
                .font(.title3)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import Document", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Import helper

    private func attachPendingFiles(to event: LSEvent) {
        for url in pendingImportURLs {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let storedName = try LSDocument.importFile(from: url)
                let doc = LSDocument(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    kind: DocumentKind.infer(from: url),
                    storedFileName: storedName
                )
                modelContext.insert(doc)
                doc.event = event
                doc.runOCRIfNeeded()
            } catch {
                importError = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        pendingImportURLs = []
    }
}

// MARK: - FilterChipButton (local alias avoids name clash)

private struct FilterChipButton: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let img = systemImage {
                    Label(label, systemImage: img)
                } else {
                    Text(label)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.glass(isSelected ? .regular.tint(.accentColor) : .regular))
    }
}

// MARK: - DocumentRowView

private struct DocumentRowView: View {
    let document: LSDocument

    var body: some View {
        HStack(spacing: 12) {
            DocumentPreviewThumbnail(document: document, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayName)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(document.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let event = document.event {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(event.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(document.importedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - EventPickerSheet

/// Lets the user choose which event to attach newly imported files to.
private struct EventPickerSheet: View {
    let events: [LSEvent]
    let onSelect: (LSEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [LSEvent] {
        guard !searchText.isEmpty else { return events }
        return events.filter { $0.title.localizedCaseInsensitiveContains(searchText)
            || ($0.entity?.name.localizedCaseInsensitiveContains(searchText) ?? false) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView("No Events", systemImage: "calendar.badge.exclamationmark",
                        description: Text("Create an event first, then import documents."))
                } else {
                    List(filtered) { event in
                        Button {
                            onSelect(event)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: event.category.systemImage)
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(.white)
                                    .background(Color.accentColor.gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.callout.weight(.medium))
                                    if let entityName = event.entity?.name {
                                        Text(entityName).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Attach to Event")
            .searchable(text: $searchText, prompt: "Search events")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 320)
    }
}

// MARK: - DocumentInspectorView

struct DocumentInspectorView: View {
    let document: LSDocument
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Preview section — shown when file is available
                if let url = document.resolvedURL() {
                    Section {
                        QuickLookPreview(url: url)
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }

                Section("File Info") {
                    LabeledContent("Name", value: document.displayName)
                    LabeledContent("Type", value: document.kind.rawValue)
                    LabeledContent("Imported", value: document.importedAt.formatted())
                    if let event = document.event {
                        LabeledContent("Event", value: event.title)
                    }
                }

                if let url = document.resolvedURL() {
                    Section {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if !document.inferredSummary.isEmpty {
                    Section("AI Summary") {
                        Text(document.inferredSummary)
                            .font(.callout)
                    }
                }
                if !document.ocrContent.isEmpty {
                    Section("Extracted Text") {
                        Text(document.ocrContent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(document.displayName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if let onDelete {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }
}
