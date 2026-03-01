import SwiftUI

/// Sheet for adding a user-defined custom property field to an entity or event.
struct AddPropertySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var valueType: PropertyValueType = .string

    let onSave: (String, PropertyValueType) -> Void

    private var isValid: Bool {
        !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Field") {
                    TextField("Field Name", text: $key)
                    Picker("Type", selection: $valueType) {
                        ForEach(PropertyValueType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.systemImage).tag(type)
                        }
                    }
                }
            }
            .navigationTitle("Add Custom Field")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(key.trimmingCharacters(in: .whitespaces), valueType)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 200)
    }
}
