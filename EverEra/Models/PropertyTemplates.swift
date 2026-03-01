import Foundation

// MARK: - PropertyTemplate

/// Compile-time definition of a suggested property field for a given entity type or event category.
/// Not persisted — only used at creation time to pre-populate LSProperty instances.
struct PropertyTemplate: Sendable {
    let key: String
    let valueType: PropertyValueType
    let placeholder: String

    init(_ key: String, _ valueType: PropertyValueType = .string, placeholder: String = "") {
        self.key = key
        self.valueType = valueType
        self.placeholder = placeholder.isEmpty ? key : placeholder
    }
}

// MARK: - PropertyTemplateStore

enum PropertyTemplateStore {

    // MARK: Entity Type Templates

    static func templates(for entityType: EntityType) -> [PropertyTemplate] {
        switch entityType {
        case .vehicle:
            return [
                PropertyTemplate("Make & Model",    .string, placeholder: "e.g. Honda Accord"),
                PropertyTemplate("Year",            .number, placeholder: "e.g. 2023"),
                PropertyTemplate("Color",           .string, placeholder: "e.g. Silver"),
                PropertyTemplate("VIN",             .string, placeholder: "e.g. 1HGCM82633A004352"),
                PropertyTemplate("License Plate",   .string, placeholder: "e.g. ABC 1234"),
            ]
        case .person:
            return [
                PropertyTemplate("Date of Birth",   .date),
                PropertyTemplate("Email",           .string, placeholder: "email@example.com"),
                PropertyTemplate("Phone",           .string, placeholder: "+1 (555) 000-0000"),
                PropertyTemplate("Relationship",    .string, placeholder: "e.g. Spouse, Parent"),
            ]
        case .employer:
            return [
                PropertyTemplate("Industry",        .string, placeholder: "e.g. Technology"),
                PropertyTemplate("Website",         .url,    placeholder: "https://"),
                PropertyTemplate("Employee ID",     .string, placeholder: "e.g. EMP-12345"),
            ]
        case .residence:
            return [
                PropertyTemplate("Address",         .string, placeholder: "Full street address"),
                PropertyTemplate("Monthly Cost",    .number, placeholder: "e.g. 2500"),
                PropertyTemplate("Sq. Footage",     .number, placeholder: "e.g. 1200"),
                PropertyTemplate("Bedrooms",        .number, placeholder: "e.g. 3"),
            ]
        case .institution:
            return [
                PropertyTemplate("Degree / Program",.string, placeholder: "e.g. B.S. Computer Science"),
                PropertyTemplate("Student ID",      .string, placeholder: "e.g. STU-98765"),
                PropertyTemplate("Website",         .url,    placeholder: "https://"),
            ]
        case .asset:
            return [
                PropertyTemplate("Serial Number",   .string),
                PropertyTemplate("Purchase Price",  .number, placeholder: "e.g. 999.99"),
                PropertyTemplate("Purchase Date",   .date),
                PropertyTemplate("Warranty Expiry", .date),
            ]
        case .project:
            return [
                PropertyTemplate("Repository URL",  .url,    placeholder: "https://github.com/"),
                PropertyTemplate("Status",          .string, placeholder: "e.g. Active, On Hold"),
            ]
        case .other:
            return []
        }
    }

    // MARK: Event Category Templates

    static func templates(for eventCategory: EventCategory) -> [PropertyTemplate] {
        switch eventCategory {
        case .employment:
            return [
                PropertyTemplate("Job Title",       .string, placeholder: "e.g. Senior Engineer"),
                PropertyTemplate("Salary",          .number, placeholder: "e.g. 120000"),
                PropertyTemplate("Manager",         .string, placeholder: "e.g. Jane Smith"),
                PropertyTemplate("Department",      .string, placeholder: "e.g. Engineering"),
            ]
        case .housing:
            return [
                PropertyTemplate("Lease Term (mo)", .number, placeholder: "e.g. 12"),
                PropertyTemplate("Security Deposit",.number, placeholder: "e.g. 2500"),
                PropertyTemplate("Landlord",        .string, placeholder: "Name or company"),
            ]
        case .health:
            return [
                PropertyTemplate("Provider",        .string, placeholder: "e.g. Dr. Smith"),
                PropertyTemplate("Policy Number",   .string, placeholder: "Insurance policy #"),
                PropertyTemplate("Diagnosis / Type",.string, placeholder: "e.g. Annual Checkup"),
            ]
        case .travel:
            return [
                PropertyTemplate("Destination",     .string, placeholder: "e.g. Tokyo, Japan"),
                PropertyTemplate("Booking Ref",     .string, placeholder: "e.g. ABC123"),
                PropertyTemplate("Carrier",         .string, placeholder: "e.g. United Airlines"),
            ]
        case .financial:
            return [
                PropertyTemplate("Amount",          .number, placeholder: "e.g. 5000"),
                PropertyTemplate("Account",         .string, placeholder: "e.g. Last 4 digits"),
                PropertyTemplate("Institution",     .string, placeholder: "e.g. Chase Bank"),
            ]
        case .education:
            return [
                PropertyTemplate("Credential",      .string, placeholder: "e.g. B.S. Computer Science"),
                PropertyTemplate("GPA",             .number, placeholder: "e.g. 3.8"),
            ]
        case .ownership:
            return [
                PropertyTemplate("Purchase Price",  .number, placeholder: "e.g. 25000"),
                PropertyTemplate("Serial / Ref #",  .string),
            ]
        case .milestone:
            return [
                PropertyTemplate("Location",        .string, placeholder: "Where it happened"),
            ]
        case .other:
            return []
        }
    }

    // MARK: Instantiation

    /// Creates `LSProperty` instances for an entity type's template, ready to be inserted.
    static func instantiateProperties(for entityType: EntityType) -> [LSProperty] {
        templates(for: entityType).enumerated().map { index, template in
            LSProperty(
                key: template.key,
                valueType: template.valueType,
                displayOrder: index,
                isTemplateField: true
            )
        }
    }

    /// Creates `LSProperty` instances for an event category's template, ready to be inserted.
    static func instantiateProperties(for eventCategory: EventCategory) -> [LSProperty] {
        templates(for: eventCategory).enumerated().map { index, template in
            LSProperty(
                key: template.key,
                valueType: template.valueType,
                displayOrder: index,
                isTemplateField: true
            )
        }
    }
}
