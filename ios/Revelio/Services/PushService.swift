import Foundation
import SwiftUI
import UIKit
import UserNotifications

// MARK: - PushService
//
// Registers for APNs, reports the device token to the backend
// (`POST /recalls/device-token`), and handles tap-through for recall
// notifications. A reference is wired into the app delegate so that
// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
// can forward the token here.

@MainActor
final class PushService: NSObject, ObservableObject {
    static let shared = PushService()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var lastRegisteredToken: String?

    private var authToken: (() -> String?)? = nil

    private var apiBase: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Called from RevelioApp / AppDelegate with a closure that returns the
    /// current JWT. Using a closure avoids retaining the AuthViewModel here
    /// and always pulls the freshest token.
    func configure(authTokenProvider: @escaping () -> String?) {
        self.authToken = authTokenProvider
    }

    /// Prompt for permission and, if granted, register with APNs. Safe to
    /// call from a SwiftUI `.task` — the registration call is main-thread.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            // Permission denied or user cancelled — no-op.
        }
    }

    /// Forwarded from the app delegate. Converts the raw token to hex and
    /// POSTs it to the backend.
    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        lastRegisteredToken = token
        Task { await reportDeviceToken(token) }
    }

    /// Forwarded from the app delegate so ops can see registration failures.
    func handleRegistrationFailure(_ error: Error) {
        #if DEBUG
        print("[PushService] APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    private func reportDeviceToken(_ token: String) async {
        guard let jwt = authToken?() else { return }
        guard let url = URL(string: "\(apiBase)/recalls/device-token") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        let payload: [String: String] = ["platform": "ios", "token": token]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code >= 400 {
                #if DEBUG
                print("[PushService] device-token upload HTTP \(code)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[PushService] device-token upload failed: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Notification delegate

extension PushService: UNUserNotificationCenterDelegate {
    /// Show recall alerts even while the app is in the foreground —
    /// recalls are urgent, banners are fine.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    /// Tap-through: post a NotificationCenter event that the SwiftUI view
    /// layer can listen for to deep-link into RecallsView.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let kind = userInfo["kind"] as? String, kind == "recall" {
            NotificationCenter.default.post(
                name: .revelioOpenRecall,
                object: nil,
                userInfo: userInfo
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let revelioOpenRecall = Notification.Name("revelio.open.recall")
}
