<EverEraCodingRules>
    <DesignSystem name="Liquid Glass UI Patterns">
        <Patterns>
            <Pattern name="Primary Action Buttons">
                <Implementation>.buttonStyle(.glass)</Implementation>
                <Usage>FAB, toolbar add buttons.</Usage>
            </Pattern>
            <Pattern name="Filter Chips">
                <Implementation>.buttonStyle(.glass(...))</Implementation>
                <Options>Optional .tint(.accentColor) when selected.</Options>
            </Pattern>
            <Pattern name="Filter Chip Container">
                <Implementation>GlassEffectContainer(spacing:) wrapping an HStack</Implementation>
            </Pattern>
            <Pattern name="Card Backgrounds">
                <Styling>.regularMaterial fill with a strokeBorder of the event's category color at 0.35 opacity, plus a 3pt colored left-edge accent bar.</Styling>
            </Pattern>
            <Pattern name="Empty States">
                <Styling>Large thin SF Symbol + secondary text + a .glass button.</Styling>
            </Pattern>
        </Patterns>
        <Constraints>
            <Constraint>Do not use .borderedProminent for primary actions (except for DocumentCenterView empty-state import button, which is a known inconsistency). Use .glass instead.</Constraint>
        </Constraints>
    </DesignSystem>

    <KnownIssues>
        <Issue id="5" title="No deduplication on archive import">
            <Description>DataExportService.importJSON is additive — re-importing the same archive creates duplicate entities. There is no UUID-based deduplication check. Agents should not "fix" this without explicit instruction, since the additive behavior is intentional per the current design.</Description>
        </Issue>
        <Issue id="7" title="EverEraJSONDocument is defined inside DataExportService.swift">
            <Description>The FileDocument-conforming EverEraJSONDocument struct lives at the bottom of DataExportService.swift. If you're looking for it, it's there — not in a separate file.</Description>
        </Issue>
        <Issue id="11" title="GlassEffectContainer is not defined in this codebase">
            <Description>It is a macOS 26 system API from the Liquid Glass design system. Do not try to implement it yourself — it is provided by the OS. If it appears missing in an older SDK, you need macOS 26 SDK.</Description>
        </Issue>
        <Issue id="12" title="AddPropertySheet — missing from this document">
            <Description>AddPropertySheet.swift exists in the project but was not fully read here. It is a simple form sheet with a key: String and valueType: PropertyValueType picker that calls an onAdd: (String, PropertyValueType) -> Void closure on save. Any agent touching property creation should read that file directly.</Description>
        </Issue>
    </KnownIssues>

    <StyleRules>
        <Rule id="1" title="Binding Mutation">
            <Requirement>All @Model class properties mutated from a view must go through @Bindable. Never use let on a model object you need to edit.</Requirement>
        </Rule>
        <Rule id="2" title="Observation Patterns">
            <Requirement>Never use objectWillChange or ObservableObject. SwiftData's @Model and @Bindable handle observation automatically.</Requirement>
        </Rule>
        <Rule id="3" title="Avoid StateObject/ObservedObject">
            <Requirement>Never create a @StateObject or @ObservedObject. These are pre-SwiftData patterns.</Requirement>
        </Rule>
        <Rule id="4" title="Lane Immutability">
            <Requirement>Lane indices are immutable. EventCategory.laneIndex values are load-bearing layout constants. Changing them will visually break the timeline.</Requirement>
        </Rule>
        <Rule id="5" title="File Storage">
            <Requirement>File storage is always via LSDocument.importFile(from:). Never write files to any other location. Never reference a file by a raw URL across sessions — always use storedFileName + storageDirectory.</Requirement>
        </Rule>
        <Rule id="6" title="Relationship Management">
            <Requirement>Relationships are always set after modelContext.insert. See Insertion Pattern above.</Requirement>
        </Rule>
        <Rule id="7" title="Summary Service Gating">
            <Requirement>SummaryService always gated by SummaryService.isAvailable. Never call summarise unconditionally.</Requirement>
        </Rule>
        <Rule id="8" title="TimelineMainView scrollProxy">
            <Requirement>TimelineMainView's scrollProxy is stored as @State. It is captured on .onAppear and reused by selectEvent(_:proxy:). Do not try to pass a proxy from outside.</Requirement>
        </Rule>
        <Rule id="9" title="handleSnapChange lifecycle">
            <Requirement>handleSnapChange must run after scroll settles. It is intentionally debounced by 280ms inside onScrollPhaseChange. Do not move it to a different lifecycle hook.</Requirement>
        </Rule>
        <Rule id="10" title="Concurrency Pattern">
            <Requirement>Do not add Combine imports. The codebase is fully async/await.</Requirement>
        </Rule>
        <Rule id="11" title="Swift 6 Strict Concurrency">
            <Requirement>Always use `Task { @MainActor in }` when accessing @Model objects from a Task closure. Never capture @Model objects with `let doc = self` — use `self` directly inside @MainActor-isolated tasks.</Requirement>
        </Rule>
        <Rule id="12" title="SwiftData Indexing">
            <Requirement>All @Model classes must have `#Unique` on their `id` property and `#Index` on frequently queried fields. Check existing models for the pattern.</Requirement>
        </Rule>
        <Rule id="13" title="Accessibility">
            <Requirement>All interactive elements (buttons, rows, cards) must have meaningful accessibility labels. Use `.accessibilityElement(children: .combine)` on composite rows and `.accessibilityLabel` on standalone controls.</Requirement>
        </Rule>
    </StyleRules>
</EverEraCodingRules>
