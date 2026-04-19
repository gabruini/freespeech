// Swift 5.0
//
//  MainTab.swift
//

import Foundation

enum MainTab: Hashable {
    case patterns
    case natural
    case drill
    case pronunciation
}

struct VideoPermissionPopoverItem: Identifiable {
    let id = UUID()
    let message: String
    let buttonLabel: String
    let settingsPane: String
}
