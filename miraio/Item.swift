//
//  Item.swift
//  miraio
//
//  Created by Ivan King on 20.08.2026.
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
