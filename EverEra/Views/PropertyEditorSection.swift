import SwiftUI
import SwiftData

// MARK: - PropertyEditorSection

/// Reusable Form section that displays and edits an array of LSProperty objects.
/// Edits auto-save via @Bindable on each LSProperty row.
struct PropertyEditorSection: View {
    let properties: [LSProperty]
    let templateSource: [PropertyTemplate]
    let onAdd: () -> Void
    let onDelete: (LSProperty) -> Void

    private var sorted: [LSProperty] {
        properties.sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        Section {
            ForEach(sorted) { property in
                PropertyFieldRow(
                    property: property,
                    placeholder: placeholder(for: property)
                )
            }
            .onDelete { offsets in
                let sortedProps = sorted
                for index in offsets {
                    onDelete(sortedProps[index])
                }
            }

            Button {
                onAdd()
            } label: {
                Label("Add Field", systemImage: "plus.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Properties")
        }
    }

    private func placeholder(for property: LSProperty) -> String {
        templateSource.first { $0.key == property.key }?.placeholder ?? property.key
    }
}

// MARK: - PropertyFieldRow

/// A single property row with a type-appropriate editing control.
struct PropertyFieldRow: View {
    @Bindable var property: LSProperty
    let placeholder: String

    var body: some View {
        LabeledContent {
            valueEditor
        } label: {
            HStack(spacing: 4) {
                Image(systemName: property.valueType.systemImage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(property.key)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch property.valueType {
        case .string:
            TextField(placeholder, text: stringBinding)
                .multilineTextAlignment(.trailing)
        case .date:
            OptionalDatePicker(date: $property.dateValue)
        case .number:
            TextField(placeholder, value: $property.numberValue, format: .number)
                .multilineTextAlignment(.trailing)
        case .url:
            TextField(placeholder, text: urlStringBinding)
                .multilineTextAlignment(.trailing)
        }
    }

    // Bindings that convert nil ↔ empty string for text fields
    private var stringBinding: Binding<String> {
        Binding(
            get: { property.stringValue ?? "" },
            set: { property.stringValue = $0.isEmpty ? nil : $0 }
        )
    }

    private var urlStringBinding: Binding<String> {
        Binding(
            get: { property.urlString ?? "" },
            set: { property.urlString = $0.isEmpty ? nil : $0 }
        )
    }
}

// MARK: - OptionalDatePicker

/// A DatePicker that gracefully handles an optional Date binding.
struct OptionalDatePicker: View {
    @Binding var date: Date?
    @State private var hasDate: Bool

    init(date: Binding<Date?>) {
        self._date = date
        self._hasDate = State(initialValue: date.wrappedValue != nil)
    }

    var body: some View {
        HStack(spacing: 6) {
            if hasDate {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date ?? Date() },
                        set: { date = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()

                Button {
                    hasDate = false
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            } else {
                Button("Set Date") {
                    date = Date()
                    hasDate = true
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
            }
        }
    }
}
