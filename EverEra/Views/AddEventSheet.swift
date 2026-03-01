//
//  AddEventSheet.swift
//  EverEra
//
//  Form sheet for creating a new LSEvent on an LSEntity.
//

import SwiftUI
import SwiftData

struct AddEventSheet: View {
    let entity: LSEntity

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: EventCategory = .employment
    @State private var notes = ""
    @State private var hasStart = true
    @State private var startDate = Date()
    @State private var hasEnd = false
    @State private var endDate = Date()

    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Info") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(EventCategory.allCases, id: \.self) { c in
                            Label(c.rawValue, systemImage: c.systemImage).tag(c)
                        }
                    }
                }
                Section("Dates") {
                    Toggle("Has start date", isOn: $hasStart)
                    if hasStart {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("Has end date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
                Section("Notes") {
                    TextField("Optional notes…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 340)
    }

    private func save() {
        let event = LSEvent(
            title: title.trimmingCharacters(in: .whitespaces),
            category: category,
            notes: notes,
            startDate: hasStart ? startDate : nil,
            endDate: hasEnd ? endDate : nil
        )
        modelContext.insert(event)
        event.entity = entity

        // Attach template properties for the chosen event category
        for prop in PropertyTemplateStore.instantiateProperties(for: category) {
            modelContext.insert(prop)
            prop.event = event
        }

        dismiss()
    }
}
