import Foundation
import Combine

@MainActor
final class AlternativesViewModel: ObservableObject {
    @Published var alternatives: [AlternativeProduct] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private let baseURL: String

    init(baseURL: String = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app") {
        self.baseURL = baseURL
    }

    func fetchAlternatives(barcode: String) async {
        guard !barcode.isEmpty else { return }
        isLoading = true
        error = nil

        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/alternatives/\(barcode)") else {
            error = "Invalid URL"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                error = "Server error"
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let wrapper = try decoder.decode(AlternativesResponse.self, from: data)
            alternatives = wrapper.alternatives
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// ─── Response wrapper ─────────────────────────────────────────────────────────

private struct AlternativesResponse: Decodable {
    let alternatives: [AlternativeProduct]
}
