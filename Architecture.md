# EverEra Architecture

## App Overview

EverEra is a macOS life-graph application that helps users chronicle their personal history through entities (people, employers, residences, vehicles, etc.), time-bound events, and attached documents. It provides a visual timeline, entity management hub, and document center with on-device OCR and AI summarisation.

## Tech Stack

- **Platform:** macOS 26.2+
- **Language:** Swift 6+ (strict concurrency enabled)
- **UI Framework:** SwiftUI with Liquid Glass design system
- **Persistence:** SwiftData (`@Model`, `#Index`, `#Unique`)
- **AI/ML:** FoundationModels (on-device summarisation), Vision (OCR)
- **Build:** Xcode 26.3

## Data Model

```
LSEntity (Person, Employer, Residence, Vehicle, ...)
  ├── [LSEvent] (cascade delete, inverse: entity)
  │     ├── [LSDocument] (cascade delete, inverse: event)
  │     └── [LSProperty] (cascade delete, inverse: event)
  └── [LSProperty] (cascade delete, inverse: entity)
```

- **LSEntity** — A long-lived real-world thing (employer, residence, vehicle, person, project, institution, asset). Has a type, name, optional location, and computed active/timeline properties.
- **LSEvent** — A time-bound occurrence anchored to an entity (employment period, lease, ownership). Has a category, start/end dates, and a duration label.
- **LSDocument** — A file asset (PDF, image, receipt, contract) attached to an event. Files are copied into the app container via `LSDocument.importFile(from:)`. Supports OCR text extraction and AI summarisation.
- **LSProperty** — A typed key-value pair (string, date, number, URL) attached to either an entity or an event. Supports display ordering and template-based creation.

All models use `#Unique` on `id` and `#Index` on frequently queried fields.

## View Layer

Navigation uses a `NavigationSplitView` with three primary surfaces:

| Surface | File | Description |
|---------|------|-------------|
| **Timeline** | `TimelineView.swift`, `TimelineLayout.swift` | Vertical scrolling timeline with colour-coded lanes, dock-style date magnification, sticky date header, snap-to-month scrolling, and expandable event cards |
| **Entity Hub** | `EntityHubView.swift` | Filterable list of all entities with type chips; opens `EntityDetailView` in a sheet |
| **Documents** | `DocumentCenterView.swift` | Filterable list of all documents with full-text search; file import with event attachment |

Supporting views:
- `SidebarView.swift` — Primary navigation with badge counts
- `ContentView.swift` — Root `NavigationSplitView` wiring
- `EntityDetailView.swift` — Full entity editor with events, properties, notes
- `DocumentPreviewView.swift` — QuickLook preview + thumbnail generation
- `PropertyEditorSection.swift` — Reusable property editor for entities and events
- `AddEntitySheet.swift`, `AddEventSheet.swift`, `AddPropertySheet.swift` — Creation sheets
- `Shared/FilterChip.swift` — Reusable glass-style filter chip

## Service Layer

| Service | Isolation | File | Purpose |
|---------|-----------|------|---------|
| `OCRService` | `actor` | `OCRService.swift` | On-device text extraction from images/PDFs via Vision framework |
| `SummaryService` | `actor` | `SummaryService.swift` | AI summarisation via FoundationModels; gated by `isAvailable` |
| `DataExportService` | `@MainActor` | `DataExportService.swift` | JSON archive export/import; also contains `EverEraJSONDocument` (FileDocument) |

## Concurrency Model

- **@MainActor** for all UI code and SwiftData model access
- **actor** isolation for services (`OCRService`, `SummaryService`)
- **async/await** throughout — no Combine
- Task closures that access `@Model` objects use `Task { @MainActor in }` for safety
- `FocusedValue`-based command actions use `@Sendable @MainActor` closures

## Design System

Liquid Glass patterns (macOS 26):
- `.buttonStyle(.glass)` for primary action buttons (FAB, toolbar)
- `.buttonStyle(.glass(.regular.tint(.accentColor)))` for selected filter chips
- `GlassEffectContainer` (system API) for filter chip bars
- `.regularMaterial` card backgrounds with category-coloured stroke borders
- Large thin SF Symbols + secondary text for empty states

## File Structure

```
EverEra/
├── EverEraApp.swift              # App entry, ModelContainer, menu commands
├── ContentView.swift             # Root NavigationSplitView
├── Models/
│   ├── LSEntity.swift            # Entity model + EntityType enum
│   ├── LSEvent.swift             # Event model + EventCategory enum
│   ├── LSDocument.swift          # Document model + DocumentKind enum + OCR/summary triggers
│   ├── LSProperty.swift          # Property model + PropertyValueType enum
│   └── PropertyTemplates.swift   # Template definitions per entity/event type
├── Views/
│   ├── SidebarView.swift         # Navigation sidebar
│   ├── TimelineView.swift        # Timeline surface (main view + all subviews)
│   ├── TimelineLayout.swift      # Timeline row/month calculation logic
│   ├── EntityHubView.swift       # Entity list + EntityRowView
│   ├── EntityDetailView.swift    # Entity detail + EventSummaryRow + EventDetailView
│   ├── DocumentCenterView.swift  # Document list + DocumentRowView + import flow
│   ├── DocumentPreviewView.swift # QuickLook wrapper + thumbnail generator
│   ├── PropertyEditorSection.swift # Reusable property editor
│   ├── AddEntitySheet.swift      # Entity creation form
│   ├── AddEventSheet.swift       # Event creation form
│   ├── AddPropertySheet.swift    # Property creation form
│   └── Shared/
│       └── FilterChip.swift      # Reusable filter chip component
├── Services/
│   ├── OCRService.swift          # Vision-based OCR (actor)
│   ├── SummaryService.swift      # FoundationModels summarisation (actor)
│   └── DataExportService.swift   # Archive export/import (@MainActor)
├── Architecture.md               # This file
└── CodingRules.md                # Style rules, constraints, known issues
```
