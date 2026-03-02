//
//  FilterChip.swift
//  EverEra
//
//  Shared filter chip button used across EntityHubView and DocumentCenterView.
//

import SwiftUI

struct FilterChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let img = systemImage {
                    Label(label, systemImage: img)
                } else {
                    Text(label)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.glass(isSelected ? .regular.tint(.accentColor) : .regular))
        .accessibilityLabel("\(label)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
