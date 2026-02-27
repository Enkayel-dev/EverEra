//
//  Item.swift
//  EverEra
//
//  Created by Nicholas Lachapelle on 2026-02-27.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
