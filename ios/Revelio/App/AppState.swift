import SwiftUI

class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var scanCount = 0
    let maxFreeScans = 10
}
