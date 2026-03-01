//
//  AddEntitySheet.swift
//  EverEra
//
//  Form sheet for creating a new LSEntity.
//  Optionally creates a first event inline so the user can capture
//  dates right at the moment of entry.
//

import SwiftUI
import SwiftData

struct AddEntitySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: Entity fields
    @State private var name = ""
    @State private var type: EntityType = .employer
    @State private var notes = ""

    // MARK: First-event toggle
    @State private var addFirstEvent = true
    @State private var eventTitle = ""
    @State private var eventCategory: EventCategory = .employment
    @State private var hasStart = true
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()
    @State private var eventNotes = ""

    private var entityNameValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var eventTitleValid: Bool {
        !addFirstEvent || !eventTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isValid: Bool { entityNameValid && eventTitleValid }

    var body: some View {
        NavigationStack {
            Form {
                entitySection
                firstEventToggleSection
                if addFirstEvent {
                    eventDetailsSection
                    eventDatesSection
                    eventNotesSection
                }
            }
            .navigationTitle("New Entity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!isValid)
                }
            }
            // Auto-fill a sensible event title when entity name changes
            .onChange(of: name) { _, newName in
                if eventTitle.isEmpty { eventTitle = newName }
            }
            // Sync category defaults with entity type
            .onChange(of: type) { _, newType in
                eventCategory = defaultCategory(for: newType)
            }
        }
        .frame(minWidth: 420, minHeight: addFirstEvent ? 480 : 280)
        .animation(.default, value: addFirstEvent)
    }

    // MARK: - Sections

    private var entitySection: some View {
        Section("Entity") {
            TextField("Name  (e.g. Acme Corp, 42 Oak St)", text: $name)
            Picker("Type", selection: $type) {
                ForEach(EntityType.allCases, id: \.self) { t in
                    Label(t.rawValue, systemImage: t.systemImage).tag(t)
                }
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var firstEventToggleSection: some View {
        Section {
            Toggle("Add a time-period event now", isOn: $addFirstEvent)
        } footer: {
            Text("Capture the start date, end date, and category for this entity's primary period — e.g. an employment term or lease.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eventDetailsSection: some View {
        Section("Event") {
            TextField("Title  (e.g. Software Engineer)", text: $eventTitle)
            Picker("Category", selection: $eventCategory) {
                ForEach(EventCategory.allCases, id: \.self) { c in
                    Label(c.rawValue, systemImage: c.systemImage).tag(c)
                }
            }
        }
    }

    private var eventDatesSection: some View {
        Section("Dates") {
            Toggle("Has start date", isOn: $hasStart)
            if hasStart {
                DatePicker("Start", selection: $startDate, displayedComponents: .date)
            }
            Toggle("Currently ongoing", isOn: Binding(
                get: { !hasEnd },
                set: { hasEnd = !$0 }
            ))
            if hasEnd {
                DatePicker(
                    "End",
                    selection: $endDate,
                    in: hasStart ? startDate... : .distantPast...,
                    displayedComponents: .date
                )
            }
        }
    }

    private var eventNotesSection: some View {
        Section("Event Notes") {
            TextField("Optional notes…", text: $eventNotes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    // MARK: - Save

    private func save() {
        let entity = LSEntity(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            notes: notes
        )
        modelContext.insert(entity)

        // Attach template properties for the chosen entity type
        for prop in PropertyTemplateStore.instantiateProperties(for: type) {
            modelContext.insert(prop)
            prop.entity = entity
        }

        if addFirstEvent {
            let event = LSEvent(
                title: eventTitle.trimmingCharacters(in: .whitespaces),
                category: eventCategory,
                notes: eventNotes,
                startDate: hasStart ? startDate : nil,
                endDate: hasEnd ? endDate : nil
            )
            modelContext.insert(event)
            event.entity = entity

            // Attach template properties for the chosen event category
            for prop in PropertyTemplateStore.instantiateProperties(for: eventCategory) {
                modelContext.insert(prop)
                prop.event = event
            }
        }

        dismiss()
    }

    // MARK: - Helpers

    private func defaultCategory(for type: EntityType) -> EventCategory {
        switch type {
        case .employer:     return .employment
        case .residence:    return .housing
        case .institution:  return .education
        case .vehicle:      return .ownership
        default:            return .other
        }
    }
}
