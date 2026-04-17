import { Router } from 'express';

export const privacyRouter = Router();

const CONTACT_EMAIL = process.env.CONTACT_EMAIL || 'privacy@revelio.app';

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c] as string));
}

const contactSafe = escapeHtml(CONTACT_EMAIL);

const PRIVACY_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Privacy Policy — Revelio</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background: #0d0d0d;
      color: #e8e8e8;
      line-height: 1.7;
      padding: 40px 20px 80px;
    }
    .container { max-width: 760px; margin: 0 auto; }
    h1 {
      font-size: 2rem;
      font-weight: 700;
      color: #ffffff;
      margin-bottom: 6px;
    }
    .subtitle {
      font-size: 0.9rem;
      color: #888;
      margin-bottom: 40px;
    }
    h2 {
      font-size: 1.15rem;
      font-weight: 600;
      color: #ffffff;
      margin: 36px 0 12px;
      padding-bottom: 8px;
      border-bottom: 1px solid #2a2a2a;
    }
    p { margin-bottom: 14px; color: #cccccc; }
    ul { margin: 0 0 14px 20px; color: #cccccc; }
    li { margin-bottom: 6px; }
    a { color: #5e9eff; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .card {
      background: #1a1a1a;
      border: 1px solid #2a2a2a;
      border-radius: 12px;
      padding: 20px 24px;
      margin-bottom: 14px;
    }
    .card-title { font-weight: 600; color: #ffffff; margin-bottom: 6px; }
    .card p { margin-bottom: 0; font-size: 0.92rem; }
    .effective { font-size: 0.85rem; color: #666; margin-top: 40px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Privacy Policy</h1>
    <p class="subtitle">Revelio &mdash; Supplement &amp; Ingredient Scanner</p>

    <p>
      Revelio ("we," "our," or "us") is committed to protecting your privacy. This policy explains
      what information we collect, how we use it, who we share it with, and what rights you have
      over your data. By using Revelio you agree to the practices described here.
    </p>

    <!-- ─── 1. Information We Collect ──────────────────────────────────────── -->
    <h2>1. Information We Collect</h2>

    <p><strong>Account information</strong></p>
    <ul>
      <li>Phone number — used solely for authentication via one-time verification codes. We do not store your full phone number beyond what is required for account identification.</li>
    </ul>

    <p><strong>Usage data</strong></p>
    <ul>
      <li>Products and supplements you scan or manually add to your pantry.</li>
      <li>Ingredient flags, health scores, and personalized preferences you configure (e.g., allergens, dietary goals).</li>
      <li>Scan history and alternative product searches.</li>
    </ul>

    <p><strong>Purchase information</strong></p>
    <ul>
      <li>Subscription status and entitlements managed through RevenueCat. We do not process or store your payment card details directly; all billing is handled by Apple (App Store) or Google (Play Store).</li>
    </ul>

    <p><strong>Device &amp; technical data</strong></p>
    <ul>
      <li>Device type, operating system version, app version, and anonymized crash/diagnostic logs used to maintain app stability.</li>
    </ul>

    <p><strong>Optional: AI analysis</strong></p>
    <ul>
      <li>If you use the AI ingredient analysis feature, ingredient text from product labels is sent to OpenAI for processing. No personally identifiable information is included in these requests.</li>
    </ul>

    <!-- ─── 2. How We Use Your Information ─────────────────────────────────── -->
    <h2>2. How We Use Your Information</h2>
    <ul>
      <li>To create and authenticate your account using phone verification.</li>
      <li>To provide core features: product scanning, ingredient analysis, pantry management, and personalized health scoring.</li>
      <li>To manage your subscription and unlock premium features.</li>
      <li>To improve app performance, fix bugs, and develop new features.</li>
      <li>To comply with legal obligations.</li>
    </ul>
    <p>We do not sell your personal information to third parties. We do not use your data for advertising or tracking across other apps or websites.</p>

    <!-- ─── 3. Third-Party Services ─────────────────────────────────────────── -->
    <h2>3. Third-Party Services</h2>
    <p>Revelio integrates with the following third-party services. Each has its own privacy policy governing its use of data.</p>

    <div class="card">
      <div class="card-title">Twilio Verify</div>
      <p>Used to send one-time SMS verification codes for phone authentication. Your phone number is transmitted to Twilio to deliver the code. Twilio does not retain your number for marketing purposes.<br/>
      <a href="https://www.twilio.com/en-us/legal/privacy" target="_blank" rel="noopener noreferrer">Twilio Privacy Policy →</a></p>
    </div>

    <div class="card">
      <div class="card-title">RevenueCat</div>
      <p>Manages in-app subscriptions and purchase receipts. RevenueCat receives your anonymized app user ID and subscription events (purchase, renewal, cancellation) to determine your entitlements. Payment details are never shared with RevenueCat directly; those remain with Apple/Google.<br/>
      <a href="https://www.revenuecat.com/privacy" target="_blank" rel="noopener noreferrer">RevenueCat Privacy Policy →</a></p>
    </div>

    <div class="card">
      <div class="card-title">OpenAI (optional feature)</div>
      <p>When you request AI-powered ingredient analysis, ingredient label text is sent to OpenAI's API. This data is processed according to OpenAI's API data usage policy. We do not send your name, phone number, or any other personal identifiers to OpenAI.<br/>
      <a href="https://openai.com/policies/privacy-policy" target="_blank" rel="noopener noreferrer">OpenAI Privacy Policy →</a></p>
    </div>

    <div class="card">
      <div class="card-title">Amazon Associates</div>
      <p>Revelio may display affiliate product links to Amazon. If you click a link and make a purchase, Amazon may use cookies or other tracking mechanisms on their site. We earn a small commission, but we do not receive any of your Amazon purchase or account data.<br/>
      <a href="https://www.amazon.com/gp/help/customer/display.html?nodeId=GX7NJQ4ZB8MHFRNJ" target="_blank" rel="noopener noreferrer">Amazon Privacy Notice →</a></p>
    </div>

    <!-- ─── 4. Data Retention ─────────────────────────────────────────────── -->
    <h2>4. Data Retention</h2>
    <p>
      We retain your account and pantry data for as long as your account remains active. If you delete your account, all personal data associated with it — including your phone number, pantry, scan history, and preferences — is permanently deleted within 30 days.
    </p>
    <p>
      Anonymized aggregate analytics and crash logs may be retained for up to 2 years to support app development.
    </p>

    <!-- ─── 5. Data Security ──────────────────────────────────────────────── -->
    <h2>5. Data Security</h2>
    <p>
      All data is transmitted over HTTPS/TLS. Authentication tokens are signed with industry-standard JWT practices. We use encrypted storage at rest for sensitive data. While we implement reasonable security measures, no method of transmission or storage is 100% secure.
    </p>

    <!-- ─── 6. Children's Privacy ─────────────────────────────────────────── -->
    <h2>6. Children's Privacy</h2>
    <p>
      Revelio is not directed at children under 13 years of age. We do not knowingly collect personal information from children under 13. If you believe we have inadvertently collected such information, please contact us immediately and we will delete it.
    </p>

    <!-- ─── 7. Your Rights ───────────────────────────────────────────────── -->
    <h2>7. Your Rights</h2>
    <p>You have the right to:</p>
    <ul>
      <li><strong>Access</strong> — request a copy of the personal data we hold about you.</li>
      <li><strong>Correction</strong> — request correction of inaccurate data.</li>
      <li><strong>Deletion</strong> — delete your account and all associated data directly within the app (Settings &rarr; Account &rarr; Delete Account), or by contacting us.</li>
      <li><strong>Portability</strong> — request an export of your data in a machine-readable format.</li>
      <li><strong>Opt-out</strong> — disable the optional AI analysis feature at any time in app settings.</li>
    </ul>
    <p>
      To exercise any of these rights, contact us at <a href="mailto:${contactSafe}">${contactSafe}</a>.
    </p>

    <!-- ─── 8. Changes to This Policy ────────────────────────────────────── -->
    <h2>8. Changes to This Policy</h2>
    <p>
      We may update this privacy policy from time to time. When we do, we will revise the effective date below and, for material changes, notify you in-app. Continued use of Revelio after updates constitutes acceptance of the revised policy.
    </p>

    <!-- ─── 9. Contact ───────────────────────────────────────────────────── -->
    <h2>9. Contact Us</h2>
    <p>
      If you have questions or concerns about this privacy policy or your data, please reach out:
    </p>
    <p>
      <strong>Email:</strong> <a href="mailto:${contactSafe}">${contactSafe}</a><br/>
      <strong>App:</strong> Revelio — Supplement &amp; Ingredient Scanner
    </p>

    <p class="effective">Effective date: March 15, 2026</p>
  </div>
</body>
</html>`;

privacyRouter.get('/', (_req, res) => {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=86400');
  res.send(PRIVACY_HTML);
});
