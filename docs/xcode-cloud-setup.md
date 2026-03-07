# Xcode Cloud Setup Guide — Revelio

> **Who this is for:** Ty. These are the manual steps to complete in App Store Connect and Xcode.
> The CI script (`.xcode-cloud/ci_scripts/ci_post_clone.sh`) is already committed and will run automatically once the workflow is connected.

---

## Prerequisites

- [ ] Apple Developer Program membership active ($99/yr)
- [ ] App registered in App Store Connect as `com.revelio.app`
- [ ] Xcode 15+ installed locally
- [ ] GitHub repo connected to Xcode Cloud (one-time OAuth setup)

---

## Step 1 — Create the App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**
2. Fill in:
   - **Platform:** iOS
   - **Name:** Revelio
   - **Primary Language:** English (U.S.)
   - **Bundle ID:** `com.revelio.app` ← must match exactly
   - **SKU:** `revelio-ios-001` (or any unique string — internal only)
3. Click **Create**

---

## Step 2 — Connect Xcode Cloud

### In Xcode (locally):

1. Open `ios/Revelio.xcodeproj` in Xcode
2. **Product** → **Xcode Cloud** → **Create Workflow**
3. Sign in with your Apple ID if prompted
4. Grant GitHub access when prompted (OAuth flow in browser)
5. Select the `revelio` repo

### Configure the workflow:

| Setting | Value |
|---------|-------|
| **Workflow Name** | Revelio CI |
| **Start Condition** | Branch Changes → `main` |
| **Environment** | macOS 14, Xcode 15.x (latest) |
| **Scheme** | Revelio |
| **Actions** | Build + Test + Archive |
| **Post-Actions** | TestFlight Internal Distribution |

---

## Step 3 — Add Environment Variables (Secrets)

In App Store Connect → **Xcode Cloud** → **Revelio CI** → **Edit Workflow** → **Environment Variables**:

| Variable Name | Value | Secret? |
|---------------|-------|---------|
| `REVELIO_API_BASE_URL` | `https://api.revelio.app` | No |
| `REVENUECAT_API_KEY` | `appl_xxxxxxxxxxxx` | **Yes** |

> **Secret variables** are encrypted and not exposed in logs. Mark any API keys as secret.

---

## Step 4 — Configure TestFlight Distribution

1. In the workflow, under **Post-Actions** → **TestFlight Internal Testing**
2. Add your Apple ID as an internal tester
3. First build requires manual review in App Store Connect before external testers

---

## Step 5 — Set Up Archive & Export (for App Store submission)

1. Add a second workflow (or extend the first) for **Release** builds:
   - **Start Condition:** Tag matches `v*` (e.g., `v1.0.0`)
   - **Actions:** Archive
   - **Post-Actions:** App Store Connect (submit for review)

2. Xcode Cloud handles signing automatically via **Automatic Signing** — no provisioning profiles needed.

---

## Step 6 — Run Your First Build

```bash
# Trigger by pushing to main
git push origin main
```

Or manually in Xcode: **Product** → **Xcode Cloud** → **Start Build**

Monitor at: [App Store Connect → Xcode Cloud → Builds](https://appstoreconnect.apple.com/teams/.../xcode-cloud)

---

## CI Script Reference

The committed CI script at `.xcode-cloud/ci_scripts/ci_post_clone.sh` runs **after** Xcode Cloud clones the repo. It:

1. Logs build environment info
2. Injects env vars into `Config.xcconfig` (API URL, RevenueCat key)
3. Sets `CFBundleVersion` from `$CI_BUILD_NUMBER`

> **Note:** If you add `Config.xcconfig`, make sure it's referenced in `Build Settings` → `Based on Configuration File` in the Xcode project. Otherwise, the injected vars won't be picked up.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Build fails: "No signing certificate" | Xcode Cloud uses automatic signing — make sure your Apple ID has the Developer role in the team |
| `ci_post_clone.sh` not running | File must be in `.xcode-cloud/ci_scripts/` and executable (`chmod +x`) |
| RevenueCat key not injected | Verify env var name matches exactly: `REVENUECAT_API_KEY` |
| TestFlight not receiving builds | Check "Post-Actions" in workflow settings — make sure TestFlight is added |

---

## Useful Links

- [Xcode Cloud Docs](https://developer.apple.com/documentation/xcode/xcode-cloud)
- [Custom Build Scripts Reference](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [App Store Connect](https://appstoreconnect.apple.com)
- [CI Environment Variable Reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)
