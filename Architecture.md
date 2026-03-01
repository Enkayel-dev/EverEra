Liquid Glass UI Patterns

• Primary action buttons: .button​Style(.glass) — used on FAB, toolbar add buttons.
• Filter chips: .button​Style(.glass(...)) with optional .tint(.accent​Color) when selected.
• Filter chip container: Glass​Effect​Container(spacing:) wrapping an HStack.
• Card backgrounds: .regular​Material fill with a stroke​Border of the event's category color at 0.35 opacity, plus a 3pt colored left-edge accent bar.
• Empty states: Use large thin SF Symbol + secondary text + a .glass button to get started.

Do not use .bordered​Prominent for primary actions in this app — use .glass. The one exception is the empty-state import button in Document​Center​View which currently uses .bordered​Prominent (this is a known inconsistency).

⸻

Known Issues & Gaps

These are real problems in the current codebase that future changes must be aware of:

1. Filter​Chip naming collision
Entity​Hub​View defines a private Filter​Chip. Document​Center​View defines a separate private Filter​Chip​Button because the names would collide. These should be consolidated into a single shared component in a new Shared​Components​.swift file.

2. Ongoing events double-counted on timeline
In events​For​Row(_:), ongoing events are added to today​Month​Key's row in addition to their start month row. However, pass​Through​Events(for:) also captures them for intermediate months. If the ongoing event started in the current month, it could appear both as a card event and as a pass-through, though the started​This​Month set filter prevents this. The logic is correct but fragile — changes to either function must be tested against all three cases: (a) event starts in today's month, (b) event started in a past month and is ongoing, (c) event started and ended in past months.

3. card​Role doesn't handle same-month start+end
Event​Month​Row​.card​Role(for:) returns .end if the event's end date is in this month, else .start. If an event starts and ends in the same month, it will be classified as .end (because the end-date check comes first), which puts the dot at the top of the card. The correct behavior is ambiguous — .start role (dot at bottom) might be more intuitive for single-month events.

4. Expanded card fixed height
card​Height(for: .expanded) returns a hard-coded 480pt. If an event has many properties or documents, the inner Scroll​View will handle overflow, but the card's bounding frame is fixed. This works fine today but will need a @​State height or View​That​Fits approach if cards ever need to adapt to content.

5. No deduplication on archive import
Data​Export​Service​.import​JSON is additive — re-importing the same archive creates duplicate entities. There is no UUID-based deduplication check. Agents should not "fix" this without explicit instruction, since the additive behavior is intentional per the current design.

6. Property display​Order gaps
When properties are deleted, display​Order values are not compacted. This is benign (sort order still works) but means re-ordering is not currently supported.

7. Ever​Era​JSONDocument is defined inside Data​Export​Service​.swift
The File​Document-conforming Ever​Era​JSONDocument struct lives at the bottom of Data​Export​Service​.swift. If you're looking for it, it's there — not in a separate file.

8. Document​Preview​Thumbnail uses QLPreview​View inline
Using QLPreview​View for 40×40 thumbnails in a scrolling list is expensive. Each list row instantiates its own NSView​Representable wrapper. This is acceptable for small document counts but will degrade performance at scale. The correct fix would be to generate static thumbnails via QLThumbnail​Generator instead.

9. No validation that event​.start​Date <= event​.end​Date
The date pickers in Add​Event​Sheet and Event​Detail​View have a in: start​Date... range constraint on the end date picker, but the expanded Event​Card inline editor uses Bindings directly with no range constraint. A user can set an end date earlier than the start date through the timeline card editor.

10. Sticky​Date​Header padding magic number
The .padding(.top, 66) on Sticky​Date​Header must stay in sync with Date​Label's lens​Y = 80. The relationship is: lens​Y(80) - half​Pill​Height(~14) = 66. If either value changes, both must be updated together.

11. Glass​Effect​Container is not defined in this codebase
It is a macOS 26 system API from the Liquid Glass design system. Do not try to implement it yourself — it is provided by the OS. If it appears missing in an older SDK, you need macOS 26 SDK.

12. Add​Property​Sheet — missing from this document
Add​Property​Sheet​.swift exists in the project (visible in the file tree) but was not fully read here. It is a simple form sheet with a key: ​String and value​Type: ​Property​Value​Type picker that calls an on​Add: (​String, ​Property​Value​Type) -> ​Void closure on save. Any agent touching property creation should read that file directly.

⸻

Style Rules — Do Not Break These

1. All @Model class properties mutated from a view must go through @Bindable. Never use let on a model object you need to edit.
2. Never use objectWillChange or ObservableObject. SwiftData's @​Model and @​Bindable handle observation automatically.
3. Never create a @StateObject or @ObservedObject. These are pre-SwiftData patterns.
4. Lane indices are immutable. Event​Category​.lane​Index values are load-bearing layout constants. Changing them will visually break the timeline.
5. File storage is always via LSDocument.importFile(from:). Never write files to any other location. Never reference a file by a raw URL across sessions — always use stored​File​Name + storage​Directory.
6. Relationships are always set after modelContext.insert. See Insertion Pattern above.
7. SummaryService always gated by SummaryService.isAvailable. Never call summarise unconditionally.
8. TimelineMainView's scrollProxy is stored as @State. It is captured on .on​Appear and reused by select​Event(_:proxy:). Do not try to pass a proxy from outside.
9. handleSnapChange must run after scroll settles. It is intentionally debounced by 280ms inside on​Scroll​Phase​Change. Do not move it to a different lifecycle hook.
10. Do not add Combine imports. The codebase is fully async/await.
