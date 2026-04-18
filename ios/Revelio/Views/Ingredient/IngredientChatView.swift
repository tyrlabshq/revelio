// REV-T3.1: Conversational ingredient AI — streaming chat UI over SSE.
// Pro-tier gated: free users see a paywall sheet instead of the composer.

import SwiftUI

// MARK: - Message model

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id = UUID()
    let role: Role
    var content: String
    var isStreaming: Bool = false
}

// MARK: - ViewModel

@MainActor
final class IngredientChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isStreaming = false
    @Published var error: String?

    let ingredient: String
    private let baseURL: String
    private var streamTask: Task<Void, Never>?

    init(
        ingredient: String,
        baseURL: String = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    ) {
        self.ingredient = ingredient
        self.baseURL = baseURL
    }

    func send(question: String, priorities: [String], token: String?) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        // History before appending the new user turn.
        let historyPayload: [[String: String]] = messages.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }

        messages.append(ChatMessage(role: .user, content: trimmed))
        let assistantIndex = messages.count
        messages.append(ChatMessage(role: .assistant, content: "", isStreaming: true))
        isStreaming = true
        error = nil

        streamTask = Task {
            await streamChat(
                question: trimmed,
                history: historyPayload,
                priorities: priorities,
                token: token,
                assistantIndex: assistantIndex
            )
            isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        isStreaming = false
    }

    // SSE parser: reads lines, accumulates "data: ..." payloads.
    private func streamChat(
        question: String,
        history: [[String: String]],
        priorities: [String],
        token: String?,
        assistantIndex: Int
    ) async {
        let encodedName = ingredient.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ingredient
        guard let url = URL(string: "\(baseURL)/ingredients/\(encodedName)/chat") else {
            error = "Invalid URL"
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let body: [String: Any] = [
            "question": question,
            "history": history,
            "priorities": priorities,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse else {
                error = "No response"
                return
            }
            if http.statusCode == 402 {
                error = "Pro subscription required"
                return
            }
            if http.statusCode != 200 {
                error = "Server error \(http.statusCode)"
                return
            }

            // SSE frames are separated by blank lines; each non-blank line is
            // a `field: value` pair. We only care about `data:` lines.
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                if line.hasPrefix("data: ") {
                    let payload = String(line.dropFirst("data: ".count))
                    if payload == "[DONE]" { break }
                    if assistantIndex < messages.count {
                        messages[assistantIndex].content += payload
                    }
                } else if line.hasPrefix("event: done") {
                    break
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        if assistantIndex < messages.count {
            messages[assistantIndex].isStreaming = false
        }
    }
}

// MARK: - View

struct IngredientChatView: View {
    let ingredient: String
    let priorities: [String]

    @StateObject private var vm: IngredientChatViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var composerText = ""
    @State private var showPaywall = false

    init(ingredient: String, priorities: [String] = []) {
        self.ingredient = ingredient
        self.priorities = priorities
        _vm = StateObject(wrappedValue: IngredientChatViewModel(ingredient: ingredient))
    }

    private var isPro: Bool {
        authViewModel.currentUser?.isPro == true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    transcript
                    Divider()
                    composer
                }
            }
            .navigationTitle(ingredient.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(authViewModel)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if vm.messages.isEmpty {
                        emptyPrompt
                    }
                    ForEach(vm.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }
                    if let err = vm.error {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(Theme.danger)
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask anything about \(ingredient.capitalized)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("Try: \"Is this safe during pregnancy?\" or \"What should I buy instead?\"")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceElevated)
        .cornerRadius(12)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask a follow-up…", text: $composerText, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .background(Theme.surfaceElevated)
                .cornerRadius(22)

            Button {
                if !isPro {
                    showPaywall = true
                    return
                }
                vm.send(
                    question: composerText,
                    priorities: priorities,
                    token: authViewModel.loadToken()
                )
                composerText = ""
            } label: {
                Image(systemName: isPro ? "arrow.up.circle.fill" : "lock.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.accent)
            }
            .disabled(vm.isStreaming || composerText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .background(Theme.surface)
    }
}

// MARK: - Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content.isEmpty && message.isStreaming ? "…" : message.content)
                .font(.system(size: 14))
                .foregroundColor(message.role == .user ? .white : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.role == .user ? Theme.accent : Theme.surfaceElevated)
                .cornerRadius(16)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    IngredientChatView(ingredient: "Red 40")
        .environmentObject(AuthViewModel())
}
