//
//  EntityDetailView.swift
//  EverEra
//
//  Full-detail view for a single LSEntity: editable name/type, events list,
//  properties, notes, and a delete action.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EntityDetailView: View {
    @Bindable var entity: LSEntity
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddEvent = false
    @State private var showingAddProperty = false
    @State private var selectedEvent: LSEvent?
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationStack {
            Form {
                entityHeaderSection
                propertiesSection
                eventsSection
                notesSection
            }
            .navigationTitle(entity.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEvent = true
                    } label: {
                        Label("Add Event", systemImage: "plus.circle")
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete Entity", systemImage: "trash")
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 400)
        .sheet(isPresented: $showingAddEvent) {
            AddEventSheet(entity: entity)
        }
        .sheet(isPresented: $showingAddProperty) {
            AddPropertySheet { key, valueType in
                let maxOrder = entity.properties.map(\.displayOrder).max() ?? -1
                let prop = LSProperty(
                    key: key,
                    valueType: valueType,
                    displayOrder: maxOrder + 1,
                    isTemplateField: false
                )
                modelContext.insert(prop)
                prop.entity = entity
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event)
        }
        .alert("Delete \"\(entity.name)\"?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(entity)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the entity and all its events and documents.")
        }
    }

    // MARK: Sections

    private var entityHeaderSection: some View {
        Section("Overview") {
            // Editable name
            LabeledContent("Name") {
                TextField("Entity name", text: $entity.name)
                    .multilineTextAlignment(.trailing)
            }

            // Editable type
            LabeledContent("Type") {
                Picker("", selection: $entity.type) {
                    ForEach(EntityType.allCases, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.systemImage).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            // Timeline span
            if let start = entity.timelineStartDate {
                LabeledContent("Since", value: start.formatted(date: .abbreviated, time: .omitted))
            }

            // Active status
            LabeledContent("Status") {
                HStack(spacing: 4) {
                    Circle()
                        .fill(entity.isActive ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(entity.isActive ? "Active" : "Closed")
                        .foregroundStyle(entity.isActive ? .green : .secondary)
                }
            }
        }
    }

    private var propertiesSection: some View {
        PropertyEditorSection(
            properties: entity.properties,
            templateSource: PropertyTemplateStore.templates(for: entity.type),
            onAdd: { showingAddProperty = true },
            onDelete: {
                modelContext.delete($0)
                entity.properties.compactDisplayOrder()
            }
        )
    }

    private var eventsSection: some View {
        Section {
            if entity.events.isEmpty {
                Button {
                    showingAddEvent = true
                } label: {
                    Label("Add first event…", systemImage: "calendar.badge.plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            } else {
                ForEach(eventsSorted) { event in
                    EventSummaryRow(event: event)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedEvent = event }
                }
                .onDelete { offsets in
                    deleteEvents(at: offsets)
                }
            }
        } header: {
            HStack {
                Text("Events (\(entity.events.count))")
                Spacer()
                Button {
                    showingAddEvent = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Add notes…", text: $entity.notes, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    // MARK: Helpers

    private var eventsSorted: [LSEvent] {
        entity.events.sorted {
            ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture)
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        let sorted = eventsSorted
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}

// MARK: - EventSummaryRow

struct EventSummaryRow: View {
    let event: LSEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.category.systemImage)
                .frame(width: 30, height: 30)
                .font(.callout)
                .foregroundStyle(.white)
                .background(event.category.color.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.callout.weight(.medium))
                HStack(spacing: 4) {
                    Text(event.durationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if event.isOngoing {
                        Text("· Ongoing")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if !event.documents.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "paperclip")
                    Text("\(event.documents.count)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.category.rawValue), \(event.durationLabel)\(event.documents.isEmpty ? "" : ", \(event.documents.count) document\(event.documents.count == 1 ? "" : "s")")")
    }
}

// MARK: - EventDetailView

/// Standalone sheet for editing an event (used from EntityDetailView).
struct EventDetailView: View {
    @Bindable var event: LSEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddProperty = false
    @State private var showingFileImporter = false
    @State private var selectedDocument: LSDocument?
    @State private var importError: String?

    private var documentsSorted: [LSDocument] {
        event.documents.sorted { $0.importedAt < $1.importedAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Editable fields
                Section("Details") {
                    LabeledContent("Title") {
                        TextField("Event title", text: $event.title)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Category") {
                        Picker("", selection: $event.category) {
                            ForEach(EventCategory.allCases, id: \.self) { cat in
                                Label(cat.rawValue, systemImage: cat.systemImage).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    LabeledContent("Start Date") {
                        DatePicker("", selection: Binding(
                            get: { event.startDate ?? Date() },
                            set: { event.startDate = $0 }
                        ), displayedComponents: .date)
                        .labelsHidden()
                    }
                    LabeledContent("End Date") {
                        HStack {
                            if event.endDate != nil {
                                DatePicker("", selection: Binding(
                                    get: { event.endDate ?? Date() },
                                    set: { event.endDate = $0 }
                                ), in: (event.startDate ?? .distantPast)...,
                                   displayedComponents: .date)
                                .labelsHidden()
                            } else {
                                Text("Ongoing").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { event.endDate != nil },
                                set: { event.endDate = $0 ? Date() : nil }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                        }
                    }
                }

                PropertyEditorSection(
                    properties: event.properties,
                    templateSource: PropertyTemplateStore.templates(for: event.category),
                    onAdd: { showingAddProperty = true },
                    onDelete: {
                        modelContext.delete($0)
                        event.properties.compactDisplayOrder()
                    }
                )

                Section("Notes") {
                    TextField("Add notes…", text: $event.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                documentsSection
            }
            .navigationTitle(event.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .png, .jpeg, .heic],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result: result)
        }
        .sheet(item: $selectedDocument) { doc in
            DocumentInspectorView(document: doc)
        }
        .sheet(isPresented: $showingAddProperty) {
            AddPropertySheet { key, valueType in
                let maxOrder = event.properties.map(\.displayOrder).max() ?? -1
                let prop = LSProperty(
                    key: key,
                    valueType: valueType,
                    displayOrder: maxOrder + 1,
                    isTemplateField: false
                )
                modelContext.insert(prop)
                prop.event = event
            }
        }
        .alert("Import Error", isPresented: .constant(importError != nil)) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var documentsSection: some View {
        Section {
            ForEach(documentsSorted) { doc in
                HStack(spacing: 10) {
                    DocumentPreviewThumbnail(document: doc, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(doc.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedDocument = doc }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                let sorted = documentsSorted
                for i in offsets { modelContext.delete(sorted[i]) }
            }

            Button {
                showingFileImporter = true
            } label: {
                Label("Attach Document", systemImage: "paperclip.badge.ellipsis")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Documents (\(event.documents.count))")
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
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
        }
    }
}
