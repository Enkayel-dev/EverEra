import Foundation
import SwiftData

// MARK: - PropertyValueType

enum PropertyValueType: String, Codable, CaseIterable, Sendable {
    case string = "String"
    case date   = "Date"
    case number = "Number"
    case url    = "URL"

    var systemImage: String {
        switch self {
        case .string: return "textformat"
        case .date:   return "calendar"
        case .number: return "number"
        case .url:    return "link"
        }
    }
}

// MARK: - LSProperty

@Model
final class LSProperty {
    #Unique<LSProperty>([\.id])
    #Index<LSProperty>([\.key])

    var id: UUID
    var key: String
    var valueType: PropertyValueType
    var displayOrder: Int

    // Only one is non-nil, determined by valueType
    var stringValue: String?
    var dateValue: Date?
    var numberValue: Double?
    var urlString: String?

    /// Whether this property was auto-generated from a template vs. user-created
    var isTemplateField: Bool

    // Back-references — only one is non-nil per instance
    var entity: LSEntity?
    var event: LSEvent?

    init(
        id: UUID = UUID(),
        key: String,
        valueType: PropertyValueType = .string,
        displayOrder: Int = 0,
        isTemplateField: Bool = false
    ) {
        self.id = id
        self.key = key
        self.valueType = valueType
        self.displayOrder = displayOrder
        self.isTemplateField = isTemplateField
    }

    // MARK: - Convenience Accessors

    var urlValue: URL? {
        get { urlString.flatMap { URL(string: $0) } }
        set { urlString = newValue?.absoluteString }
    }

    /// Human-readable display value regardless of type
    var displayValue: String {
        switch valueType {
        case .string: return stringValue ?? ""
        case .date:   return dateValue?.formatted(date: .abbreviated, time: .omitted) ?? ""
        case .number:
            if let n = numberValue {
                // Show as integer when there's no fractional part
                return n.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(n))
                    : String(n)
            }
            return ""
        case .url:    return urlString ?? ""
        }
    }

    /// Returns true if the property has any value set
    var hasValue: Bool {
        switch valueType {
        case .string: return !(stringValue ?? "").isEmpty
        case .date:   return dateValue != nil
        case .number: return numberValue != nil
        case .url:    return !(urlString ?? "").isEmpty
        }
    }
}

// MARK: - Array helpers

extension Array where Element: LSProperty {
    /// Re-indexes `displayOrder` to 0, 1, 2, … based on current sort order.
    /// Call after deleting a property to avoid gaps in the sequence.
    func compactDisplayOrder() {
        for (index, property) in sorted(by: { $0.displayOrder < $1.displayOrder }).enumerated() {
            property.displayOrder = index
        }
    }
}
