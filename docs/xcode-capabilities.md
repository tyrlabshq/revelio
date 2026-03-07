# Xcode Capabilities Checklist — Revelio

> **Who this is for:** Ty. These are the capabilities you need to enable manually in Xcode before submitting to the App Store.
> These cannot be scripted — they require your Apple Developer account credentials via Xcode.

---

## How to Enable Capabilities

1. Open `ios/Revelio.xcodeproj` in Xcode
2. Click the **Revelio** project in the navigator (top-level, not a folder)
3. Select the **Revelio** target
4. Go to the **Signing & Capabilities** tab
5. Click **+ Capability** to add each one below

---

## Required Capabilities

### ✅ Push Notifications

**Why:** Required for sending scan reminders, pantry restock alerts, and promotional notifications (Revelio Pro features).

**Steps:**
1. Click **+ Capability** → search "Push Notifications" → Add
2. This creates an `Revelio.entitlements` file with `aps-environment` set to `development`
3. For production builds, Xcode Cloud will automatically use `production` entitlement

**Backend integration:**
- Upload APNs auth key (.p8) to your push notification service (e.g., Firebase, OneSignal)
- Key ID and Team ID found at developer.apple.com → Certificates, IDs & Profiles → Keys

**Entitlement added:**
```xml
<key>aps-environment</key>
<string>development</string>
```

---

### ✅ Sign in with Apple

**Why:** Required by App Store Review Guidelines if you offer any third-party sign-in (phone auth via Supabase counts as a social-adjacent flow). Also gives users a privacy-preserving login option.

**Steps:**
1. Click **+ Capability** → search "Sign in with Apple" → Add
2. No additional configuration needed in Xcode — the entitlement handles it

**Code integration:**
- Add `AuthenticationServices` framework
- Implement `ASAuthorizationAppleIDProvider` flow in `AuthViewModel.swift`
- Validate identity tokens server-side via Supabase Apple OAuth provider

**Entitlement added:**
```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

**App Store Connect setup:**
1. Go to App Store Connect → Your App → App Information
2. Under **Sign in with Apple**, enable it
3. Also enable at developer.apple.com → Identifiers → com.revelio.app → Capabilities → Sign in with Apple

---

### ✅ In-App Purchase (for RevenueCat)

**Why:** Revelio Pro is a subscription. Any subscription or purchase requires the In-App Purchase capability.

**Steps:**
1. Click **+ Capability** → search "In-App Purchases" → Add
2. No entitlement file change — IAP is automatically enabled via App ID configuration

**RevenueCat setup:**
1. Install RevenueCat SDK: Add Swift Package `https://github.com/RevenueCat/purchases-ios.git`
2. Initialize in `RevelioApp.swift`:
   ```swift
   import RevenueCat
   
   Purchases.configure(withAPIKey: "appl_xxxxxxxxxxxx")
   ```
3. Create products in App Store Connect → Subscriptions:
   - `revelio_pro_monthly` — $4.99/month
   - `revelio_pro_annual` — $39.99/year (save 33%)
4. Mirror product IDs in RevenueCat dashboard
5. Add `REVENUECAT_API_KEY` to Xcode Cloud environment variables (see `docs/xcode-cloud-setup.md`)

**Entitlement:** No additional `.entitlements` entry needed — IAP is enabled at the App ID level.

---

## Optional Capabilities (Future)

| Capability | When to Add | Why |
|------------|-------------|-----|
| **HealthKit** | Revelio v2 | Sync health goals with Apple Health |
| **Siri** | Revelio v2 | "Hey Siri, scan this product" |
| **App Groups** | Widget support | Share scan data between app and widget extension |
| **Widget Extension** | v1.5 | Home screen scan shortcut / pantry score widget |
| **Background App Refresh** | v1.5 | Update pantry scores silently |

---

## Verification Checklist (Before Submission)

- [ ] Push Notifications capability added
- [ ] Sign in with Apple capability added
- [ ] In-App Purchases capability added (auto via App ID)
- [ ] `Revelio.entitlements` file committed to repo
- [ ] App ID at developer.apple.com reflects all enabled capabilities
- [ ] Provisioning profile regenerated after capability changes
- [ ] RevenueCat SDK integrated and configured
- [ ] APNs key uploaded to push notification service
- [ ] Sign in with Apple enabled in App Store Connect

---

## Entitlements File Location

After enabling capabilities, Xcode creates:
`ios/Revelio/Revelio.entitlements`

This file must be committed to the repo. Xcode Cloud uses it during the build/sign process.

---

## Useful Links

- [Configuring Capabilities (Apple Docs)](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app)
- [RevenueCat iOS SDK Quickstart](https://www.revenuecat.com/docs/getting-started/quickstart/ios)
- [Sign in with Apple Implementation Guide](https://developer.apple.com/documentation/sign_in_with_apple/implementing_user_authentication_with_sign_in_with_apple)
- [Push Notifications Setup](https://developer.apple.com/documentation/usernotifications)
