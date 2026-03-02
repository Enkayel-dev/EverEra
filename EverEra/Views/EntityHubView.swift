//
//  EntityHubView.swift
//  EverEra
//
//  A grid/list of all LSEntity objects, filterable by EntityType.
//  Selecting an entity opens EntityDetailView in a sheet.
//

import SwiftUI
import SwiftData

// MARK: - EntityHubView

struct EntityHubView: View {
    @Query(sort: \LSEntity.name, order: .forward) private var entities: [LSEntity]
    @State private var typeFilter: EntityType? = nil
    @State private var searchText = ""
    @State private var selectedEntity: LSEntity?
    @State private var showingAddEntity = false

    private var filtered: [LSEntity] {
        entities.filter { entity in
            let matchesType = typeFilter == nil || entity.type == typeFilter
            let matchesSearch = searchText.isEmpty
                || entity.name.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            typeFilterBar
            Divider()

            if filtered.isEmpty {
                emptyState
            } else {
                entityList
            }
        }
        .navigationTitle("Entity Hub")
        .searchable(text: $searchText, prompt: "Search entities")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddEntity = true
                } label: {
                    Label("Add Entity", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
        .sheet(isPresented: $showingAddEntity) {
            AddEntitySheet()
        }
        .sheet(item: $selectedEntity) { entity in
            EntityDetailView(entity: entity)
        }
    }

    // MARK: Type filter chips

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    FilterChip(label: "All", isSelected: typeFilter == nil) {
                        typeFilter = nil
                    }
                    ForEach(EntityType.allCases, id: \.self) { type in
                        FilterChip(
                            label: type.rawValue,
                            systemImage: type.systemImage,
                            isSelected: typeFilter == type
                        ) {
                            typeFilter = (typeFilter == type) ? nil : type
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: Entity list

    private var entityList: some View {
        List(filtered, selection: $selectedEntity) { entity in
            EntityRowView(entity: entity)
                .tag(entity)
        }
        .listStyle(.inset)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No entities yet." : "No results for \"\(searchText)\".")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - EntityRowView

struct EntityRowView: View {
    let entity: LSEntity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entity.type.systemImage)
                .frame(width: 32, height: 32)
                .font(.title3)
                .foregroundStyle(.white)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(entity.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entity.isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entity.events.count) event\(entity.events.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entity.name), \(entity.type.rawValue)\(entity.isActive ? ", active" : ""), \(entity.events.count) event\(entity.events.count == 1 ? "" : "s")")
    }
}
