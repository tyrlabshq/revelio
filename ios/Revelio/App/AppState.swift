import SwiftUI

class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isPro = false
    @Published var scanCount = 0
    let maxFreeScans = 10
    var canScan: Bool { isPro || scanCount < maxFreeScans }
}
