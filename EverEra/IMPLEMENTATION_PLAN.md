# EverEra — Implementation Plan

**Platform:** macOS 26 · **UI:** SwiftUI + Liquid Glass · **Storage:** SwiftData
**Reference prototype:** `Personal_Timeline.html` (HTML/JS single-page app, IndexedDB)
**Principle:** Apple-native APIs only. No third-party packages.

---

## 1. What We Are Building

EverEra is a **personal life-record system** for macOS. It lets a user build an ordered,
structured archive of every major life event — jobs, residences, vehicles, education,
milestones — and attach real documents (PDFs, scanned receipts, contracts) to each event.

The HTML prototype demonstrates the exact desired mental model:

- A **vertical timeline** where every event occupies a moment in calendar time.
- Each event has a **start dot** and an **end dot** on a vertical lane; a coloured line
  connects them. Start cards float _above_ the date line; end cards sit _below_ it.
- Clicking a card progresses it through three states: collapsed → summary → full-edit.
- Events are grouped into typed **Entities** (Employer, Residence, Vehicle, etc.) with
  the entity acting as a container that owns all related events.
- Each event type has a predefined set of **structured fields** (category schema) that
  auto-populate a form; free-form notes are always available.
- Documents (PDFs, images, receipts) are attached to events and stored locally inside
  the app container. No cloud upload, no external services during data entry.

The native macOS app must deliver the same conceptual experience using SwiftUI idioms,
Liquid Glass aesthetics, and SwiftData persistence.

---

## 2. Current State of the Codebase

### 2.1 Data models — COMPLETE

| Model | File | Status |
|-------|------|--------|
| `LSEntity` | `Models/LSEntity.swift` | ✅ Done |
| `LSEvent` | `Models/LSEvent.swift` | ✅ Done |
| `LSDocument` | `Models/LSDocument.swift` | ✅ Done |
| `LSProperty` | `Models/LSProperty.swift` | ✅ Done |
| `PropertyTemplates` | `Models/PropertyTemplates.swift` | ✅ Done |

All SwiftData `@Model` classes are defined, relationships are set (cascade-delete where
appropriate), and helper computed properties (`durationLabel`, `isActive`, `resolvedURL`,
etc.) exist.

### 2.2 Views — SCAFFOLDED (partial)

| View | File | Status |
|------|------|--------|
| `ContentView` | `ContentView.swift` | ✅ Shell done |
| `SidebarView` | `Views/SidebarView.swift` | ✅ Done |
| `TimelineMainView` + `TimelineLaneRow` + `TimelineEventChip` | `Views/TimelineView.swift` | ⚠️ Layout only, no real timeline geometry |
| `EventDetailSheet` | inside `TimelineView.swift` | ⚠️ Form only — no inline expand |
| `EntityHubView` | `Views/EntityHubView.swift` | ⚠️ Needs filter/search polish |
| `EntityDetailView` | `Views/EntityDetailView.swift` | ⚠️ Functional but minimal |
| `DocumentCenterView` | `Views/DocumentCenterView.swift` | ⚠️ Needs search + kind filter |
| `DocumentPreviewView` | `Views/DocumentPreviewView.swift` | ⚠️ QuickLook wrapper exists |
| `AddEntitySheet` | `Views/AddEntitySheet.swift` | ✅ Functional |
| `AddEventSheet` | `Views/AddEventSheet.swift` | ✅ Functional |
| `AddPropertySheet` | `Views/AddPropertySheet.swift` | ✅ Functional |
| `PropertyEditorSection` | `Views/PropertyEditorSection.swift` | ✅ Done |

### 2.3 App entry point — COMPLETE

`EverEraApp.swift` configures the `ModelContainer` with all four models.

---

## 3. Data Model — Final Schema

No changes to models are needed. The schema below is the source of truth.

```
LSEntity
  ├─ id: UUID
  ├─ name: String
  ├─ type: EntityType  (Person | Employer | Residence | Vehicle | Project | Institution | Asset | Other)
  ├─ notes: String
  ├─ createdAt: Date
  ├─ locationLatitude / locationLongitude / locationLabel: Optional<Double/String>
  ├─ events: [LSEvent]   (cascade-delete)
  └─ properties: [LSProperty]  (cascade-delete)

LSEvent
  ├─ id: UUID
  ├─ title: String
  ├─ category: EventCategory  (Employment | Housing | Education | Ownership | Health | Travel | Financial | Milestone | Other)
  ├─ notes: String
  ├─ startDate: Date?
  ├─ endDate: Date?   (nil = ongoing)
  ├─ entity: LSEntity?   (back-reference)
  ├─ documents: [LSDocument]  (cascade-delete)
  └─ properties: [LSProperty]  (cascade-delete)

LSProperty
  ├─ id: UUID
  ├─ key: String
  ├─ valueString / valueDate / valueNumber: Optional
  ├─ valueType: PropertyValueType  (string | date | number | url)
  ├─ displayOrder: Int
  ├─ isTemplateField: Bool
  ├─ entity: LSEntity?   (back-reference)
  └─ event: LSEvent?     (back-reference)

LSDocument
  ├─ id: UUID
  ├─ displayName: String
  ├─ kind: DocumentKind  (PDF | Image | Receipt | Contract | TaxForm | Insurance | Other)
  ├─ storedFileName: String?   (UUID-prefixed file in ~/Library/Application Support/EverEra/ImportedFiles/)
  ├─ bookmarkData: Data?   (legacy fallback)
  ├─ ocrContent: String   (on-device Vision OCR; populated async)
  ├─ inferredSummary: String  (future: FoundationModels / Apple Intelligence)
  ├─ importedAt: Date
  └─ event: LSEvent?  (back-reference)
```

---

## 4. EventCategory Color Palette

Map each category to a SwiftUI `Color` constant (mirroring the HTML prototype's SCHEMA):

| Category | Hex | SwiftUI |
|----------|-----|---------|
| Employment | `#22C55E` | `.green` |
| Housing | `#4A90D9` | `.blue` |
| Education | `#F59E0B` | `.yellow` / `.orange` |
| Ownership / Vehicle | `#A855F7` | `.purple` |
| Health | `#EF4444` | `.red` |
| Travel | `#06B6D4` | `.cyan` |
| Financial | `#10B981` | `.mint` |
| Milestone | `#EC4899` | `.pink` |
| Other | `#8B949E` | `.secondary` |

Add a `var color: Color` computed property to `EventCategory` in `LSEvent.swift`.

---

## 5. Implementation Phases

### Phase 1 — EventCategory Color + Model Polish

**Files:** `LSEvent.swift`

1. Add `var color: Color` to `EventCategory` using the palette above.
2. Keep existing `accentColorName` for backwards compatibility or remove it.
3. Verify `durationLabel` handles `nil` startDate gracefully.

---

### Phase 2 — True Vertical Timeline (core feature)

**Files:** `Views/TimelineView.swift`

This is the most important view. The HTML prototype's layout engine is the reference.
Implement it as a SwiftUI `Canvas`-based render or a pure `GeometryReader` + absolute
positioning approach. The Canvas approach is preferred for macOS 26 because it avoids
the performance cost of thousands of view instances.

#### 2A — Layout Engine

Create a `TimelineLayout` value type (in a new `Views/TimelineLayout.swift` file):

```swift
struct TimelineLayout {
    struct DateRow { var date: Date; var y: CGFloat; var events: [LSEvent] }
    struct LaneSegment { var event: LSEvent; var lane: Int; var startY: CGFloat; var endY: CGFloat; var ongoing: Bool }
    struct MonthRow { var year: Int; var month: Int; var y: CGFloat; var height: CGFloat }

    let months: [MonthRow]
    let dateRows: [DateRow]
    let segments: [LaneSegment]
    let totalHeight: CGFloat
    let numLanes: Int
    let todayY: CGFloat
}

extension TimelineLayout {
    static func compute(events: [LSEvent], focusedDate: Date?) -> TimelineLayout { … }
}
```

Algorithm (ported from HTML `layoutTimeline()`):

1. Collect all unique `startDate` and `endDate` (nil → today) values → sorted unique
   dates descending (newest at top = smallest Y, oldest at bottom = largest Y).
2. For each date, calculate the max card height above (start cards) and below (end cards).
   Default card height = 72 pt. Focused card height = 140 pt.
3. Assign Y positions accumulating from top to bottom.
4. For each month that contains dates, insert a month-header row.
5. Lane assignment: interval-graph greedy coloring. Sort events by startDate; assign to
   the first lane with no overlap.
6. Return the full layout struct.

#### 2B — Timeline Canvas Render

Inside `TimelineMainView`, replace `LazyVStack` with a `ScrollView` containing a `Canvas`:

```
ScrollView([.vertical]) {
    ZStack(alignment: .topLeading) {
        Canvas { context, size in
            // Draw month lines and labels
            // Draw date lines and date labels
            // Draw lane lines (coloured vertical bars per segment)
            // Draw lane dots (start = hollow ring, end = filled)
        }
        // Overlay: event cards (SwiftUI views at absolute positions)
        ForEach(layout.segments) { seg in
            EventStartCard(event: seg.event)
                .offset(x: cardX(lane: seg.lane), y: seg.startY - cardHeight)
            if !seg.ongoing {
                EventEndCard(event: seg.event)
                    .offset(x: cardX(lane: seg.lane), y: seg.endY)
            }
        }
    }
    .frame(height: layout.totalHeight)
}
```

**Card sizing:**
- `LABEL_AREA` = 160 pt (left gutter for date labels)
- `LANE_W` = 20 pt per lane
- `CARD_LEFT` = `LABEL_AREA + numLanes * LANE_W + 16`
- Cards fill width from `CARD_LEFT` to container width − 16

#### 2C — EventCard States

Each event produces a `EventCard` view with three presentation states (matching the HTML):

| State | Trigger | Content |
|-------|---------|---------|
| Collapsed | Default | Title + category badge + date |
| Focused | Single click | + summary fields from PropertyTemplate |
| Expanded | Double-click or "Edit" button | Full edit form inline |

Use `@State private var cardState: [UUID: CardState]` in the parent or pass via
`@Binding`. Cards in expanded state use a `popover` or grow in place.

For macOS 26, use `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))`
on each card background.

#### 2D — Sticky Date Lens

A `TimelineView`-local `@State private var snappedDate: Date?` tracks the currently
"snapped" date. A sticky overlay at the top of the scroll area shows the snapped date.
Use `ScrollView`'s `onScrollGeometryChange` (macOS 15+) or a `GeometryReader` + `PreferenceKey` approach to track scroll position and update the snapped date.

#### 2E — Drag-to-Resize (Phase 2 stretch goal)

Drag the start or end lane-dot vertically to change an event's date. Use `.gesture(DragGesture())` on lane dots. Snap to existing date rows within 20 pt. Update the SwiftData model directly inside the gesture's `onEnded` handler.

---

### Phase 3 — EventCard Inline Edit

**Files:** `Views/TimelineView.swift` (EventCard sub-view)

When an `EventCard` is in the Expanded state:

1. Show a mini-form with: Title (TextField), Category (Picker), Start Date (DatePicker),
   End Date (DatePicker + "Ongoing" toggle), Notes (TextField multiline).
2. Show `PropertyEditorSection` below.
3. Show `DocumentAttachmentRow` list with an "Attach" button that triggers `.fileImporter`.
4. Footer row: "Delete Event" (destructive) | "Cancel" | "Save" (applies changes to
   SwiftData model).

Use `@Bindable var event: LSEvent` to drive all field bindings without an intermediate
copy — changes auto-save via SwiftData's autosave.

---

### Phase 4 — Entity Hub View Polish

**Files:** `Views/EntityHubView.swift`

Current state: basic grid. Required additions:

1. **Search bar** — `.searchable(text: $searchText)` filtering by entity name.
2. **Type filter chips** — horizontal `ScrollView` of pill buttons for each `EntityType`.
   Active filter highlighted with `.glassEffect`.
3. **Entity card** — show name, type icon, event count, active/closed badge.
4. **Tap to open** `EntityDetailView` as a sheet (or NavigationLink for split view).
5. **Swipe/right-click to delete** entity (with confirmation alert).

---

### Phase 5 — Entity Detail View Polish

**Files:** `Views/EntityDetailView.swift`

Current state: Form with basic sections. Required additions:

1. **Inline property editing** — `PropertyEditorSection` is already present; verify
   all property types (string, date, number, URL) render correct editors.
2. **Events list** — show each event as `EventSummaryRow`; tap opens `EventDetailSheet`.
3. **Delete entity** — destructive toolbar button with confirmation.
4. **Edit entity name/type** — make name and type editable in the form header.
5. **Active status indicator** — green dot for active, grey for closed.

---

### Phase 6 — Document Center View

**Files:** `Views/DocumentCenterView.swift`

Required features (per HTML prototype intent):

1. **Search** — `.searchable` filtering across `displayName`, `ocrContent`,
   `inferredSummary`.
2. **Kind filter** — segmented control or pill row for each `DocumentKind`.
3. **Document rows** — thumbnail (via `DocumentPreviewThumbnail`), name, kind badge,
   event association label, import date.
4. **Inspector panel** — clicking a document opens a trailing inspector with:
   - `DocumentPreviewView` (QuickLook via `NSViewRepresentable`)
   - OCR text (expandable)
   - AI summary field (editable placeholder for future FoundationModels integration)
   - "Reveal in Finder" button (`NSWorkspace.shared.selectFile`)
   - "Delete" button
5. **Import** — "Import Document" toolbar button triggers `.fileImporter` then presents
   an event picker sheet (`EventPickerSheet`) to assign the doc to an event.
6. **EventPickerSheet** — lists all events (grouped by entity) in a searchable list.
   On selection, sets `doc.event = pickedEvent`.

---

### Phase 7 — OCR Pipeline

**Files:** `Services/OCRService.swift` (new file)

Use Apple's `Vision` framework (`VNRecognizeTextRequest`) to extract text from imported
PDFs and images.

```swift
actor OCRService {
    func extractText(from url: URL) async throws -> String {
        // For images: VNImageRequestHandler + VNRecognizeTextRequest
        // For PDFs: iterate pages via PDFKit, render each to CGImage, run VNRecognizeTextRequest
        // Return concatenated string
    }
}
```

Trigger from `DocumentCenterView` and `EventDetailSheet` after import:

```swift
Task {
    doc.ocrContent = try await OCRService.shared.extractText(from: url)
}
```

---

### Phase 8 — Export / Import (JSON Backup)

**Files:** `Services/DataExportService.swift` (new file)

Match the HTML prototype's "Export JSON" / "Import JSON" feature.

**Export:**
```swift
struct EverEraExport: Codable {
    var entities: [EntityExport]
}
struct EntityExport: Codable {
    var id: UUID; var name: String; var type: String; var notes: String
    var events: [EventExport]
    var properties: [PropertyExport]
}
// ... EventExport, PropertyExport, DocumentExport
```

Trigger via `Commands` → File → Export… using `fileExporter` modifier with `UTType.json`.

**Import:**
- Use `fileImporter` to pick a JSON file.
- Decode into the export structs.
- Walk the tree and insert `LSEntity`/`LSEvent`/`LSProperty` into the model context.
- Documents: embed base64-encoded file data in the JSON for portability.

---

### Phase 9 — Apple Intelligence / FoundationModels Integration

**Files:** `Services/SummaryService.swift` (new file)

Use the `FoundationModels` framework (macOS 26, on-device) to generate structured
summaries of imported documents.

```swift
import FoundationModels

@Generable
struct DocumentSummary {
    var keyFacts: [String]
    var suggestedTitle: String
    var datesMentioned: [String]
}

actor SummaryService {
    func summarize(ocrText: String) async throws -> DocumentSummary {
        let session = LanguageModelSession()
        return try await session.respond(
            to: "Extract key facts from this document: \(ocrText)",
            generating: DocumentSummary.self
        )
    }
}
```

Store the result in `doc.inferredSummary` as a JSON string or expand the model to hold
structured fields. Display in the document inspector.

> **Note:** Search Apple Developer Documentation for the latest `FoundationModels` API
> before implementing — this framework is new in macOS 26 and details may differ from
> training data.

---

### Phase 10 — Liquid Glass & Visual Polish

Apply macOS 26 Liquid Glass materials throughout:

1. **Sidebar** — handled automatically by NavigationSplitView on macOS 26.
2. **Event cards** — `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))`
3. **FAB** — `.buttonStyle(.glass)` (already in place).
4. **Category badges** — tinted glass: `.background(event.category.color.opacity(0.15))`
   with `.glassEffect(.thin, in: Capsule())`.
5. **Sheet headers** — `GlassEffectContainer` wrapping the navigation bar area.
6. **Date lens** (sticky date indicator in timeline) — glass capsule at top of scroll.
7. **Toolbar buttons** — `.buttonStyle(.glass)` where appropriate.

---

## 6. File & Folder Structure (Final)

```
EverEra/
├── EverEra/
│   ├── EverEraApp.swift
│   ├── ContentView.swift
│   ├── Models/
│   │   ├── LSEntity.swift
│   │   ├── LSEvent.swift        ← add Color computed property (Phase 1)
│   │   ├── LSDocument.swift
│   │   ├── LSProperty.swift
│   │   └── PropertyTemplates.swift
│   ├── Views/
│   │   ├── SidebarView.swift
│   │   ├── TimelineView.swift           ← major rewrite (Phase 2-3)
│   │   ├── TimelineLayout.swift         ← NEW layout engine (Phase 2A)
│   │   ├── EntityHubView.swift          ← polish (Phase 4)
│   │   ├── EntityDetailView.swift       ← polish (Phase 5)
│   │   ├── DocumentCenterView.swift     ← polish (Phase 6)
│   │   ├── DocumentPreviewView.swift
│   │   ├── AddEntitySheet.swift
│   │   ├── AddEventSheet.swift
│   │   ├── AddPropertySheet.swift
│   │   ├── PropertyEditorSection.swift
│   │   └── EventPickerSheet.swift       ← NEW (Phase 6)
│   └── Services/
│       ├── OCRService.swift             ← NEW (Phase 7)
│       ├── DataExportService.swift      ← NEW (Phase 8)
│       └── SummaryService.swift         ← NEW (Phase 9)
```

---

## 7. Key macOS 26 APIs to Use

| Feature | API |
|---------|-----|
| Persistent storage | `SwiftData` (`@Model`, `@Query`, `ModelContainer`) |
| Glass materials | `.glassEffect(_:in:)`, `.buttonStyle(.glass)`, `GlassEffectContainer` |
| Async/await concurrency | Swift structured concurrency (no Combine) |
| File import | `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:)` |
| File export | `.fileExporter(isPresented:document:contentType:)` |
| Quick Look | `QuickLookPreview` (SwiftUI native, check if available macOS 26) or `NSViewRepresentable` wrapping `QLPreviewView` |
| OCR | `Vision` framework — `VNRecognizeTextRequest`, `VNImageRequestHandler` |
| PDF rendering | `PDFKit` — `PDFDocument`, `PDFPage.thumbnail(of:for:)` |
| On-device AI | `FoundationModels` — `LanguageModelSession`, `@Generable` macro |
| Scroll geometry | `onScrollGeometryChange` (macOS 15+) |
| Drag gesture | `.gesture(DragGesture(minimumDistance:coordinateSpace:))` |
| Canvas drawing | `Canvas { context, size in … }` |
| Open in Finder | `NSWorkspace.shared.selectFile(_:inFileViewerRootedAtPath:)` |

---

## 8. Priority Order

1. **Phase 1** — Color palette (30 min, unblocks all visual work)
2. **Phase 2** — True vertical timeline (core differentiator, implement first)
3. **Phase 3** — Inline event editing (direct consequence of Phase 2 cards)
4. **Phase 4 & 5** — Entity Hub + Detail polish (parallel, independent)
5. **Phase 6** — Document Center (depends on OCR service from Phase 7)
6. **Phase 7** — OCR (can be stubbed with empty string, fill in later)
7. **Phase 8** — Export/Import (important but not blocking)
8. **Phase 9** — FoundationModels (progressive enhancement, implement last)
9. **Phase 10** — Liquid Glass polish (apply throughout as each phase completes)

---

## 9. HTML Prototype → Native macOS Mapping

| HTML concept | Native macOS equivalent |
|---|---|
| `SCHEMA` per category | `PropertyTemplates.swift` (already exists) |
| IndexedDB | SwiftData `ModelContainer` |
| Lane overlap greedy algorithm | `TimelineLayout.compute()` interval coloring |
| Vertical date axis (px/month) | SwiftUI `Canvas` + layout engine |
| `sticky-date` lens | `ScrollView` + `onScrollGeometryChange` overlay |
| Card small → medium → full | `CardState` enum + `@State` per event UUID |
| Drag dot to resize | `DragGesture` on lane-dot views |
| `ev-card.expanded` inline form | SwiftUI conditional form expansion in card |
| IndexedDB files (ArrayBuffer) | File copy to app container (`LSDocument.importFile`) |
| Export JSON / Import JSON | `DataExportService` + `fileExporter`/`fileImporter` |
| Modal (Add/Edit event) | SwiftUI `.sheet` |

---

## 10. Notes & Decisions

- **No Combine.** All async work uses Swift `async`/`await` and `Task {}`.
- **No third-party packages.** Everything is Apple frameworks.
- **Files stay local.** Documents are copied into `~/Library/Application Support/EverEra/ImportedFiles/`.
  The user can reveal them in Finder. No iCloud sync in v1 (can be added via `SwiftData`'s
  CloudKit integration later by simply changing the `ModelContainer` configuration).
- **FoundationModels is macOS 26 only.** Gate behind `#available(macOS 26, *)` and
  fall back to an empty summary string on older OS versions (though the minimum
  deployment target should be macOS 26).
- **Canvas vs. LazyVStack for timeline.** For small data sets (< 500 events) `LazyVStack`
  with absolute offsets via `GeometryReader` is simpler. For larger data sets, `Canvas`
  with overlaid SwiftUI event card views is better. Design `TimelineLayout` to work
  with either rendering strategy so we can switch without data-layer changes.
- **SwiftData autosave.** Set `modelContainer(isAutosaveEnabled: true)` (default).
  All `@Bindable` edits auto-save; no explicit save calls needed except after bulk
  operations.
