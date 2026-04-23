import { Router } from 'express';

export const wellKnownRouter = Router();

// ─── iOS Universal Links ──────────────────────────────────────────────────────
// Apple fetches /.well-known/apple-app-site-association from the web at
// install time and on app launch. Requirements:
//   • Must be served over HTTPS with no redirects.
//   • Content-Type MUST be application/json (NOT application/json-ld, NOT
//     text/json — Apple's fetcher rejects anything else silently).
//   • No .json extension on the URL.
//
// The `applinks` payload binds the bundle identifier to one or more URL paths.
// We match every /p/<barcode> landing URL; the app's UniversalLinkHandler
// parses the path and routes to the scan result screen.
//
// The `appclips` payload advertises the same /p/* pattern for the App Clip
// target (bundle `app.revelio.Revelio.Clip`). When a user taps a
// revelio.app/p/<barcode> link without the full app installed, iOS fetches
// this manifest, sees the `appclips` stanza, and presents the App Clip card.
// Once the full app is installed, iOS prefers the `applinks` entry and hands
// the URL off to the main app via NSUserActivityTypeBrowsingWeb.
//
// Sample response:
//   {
//     "applinks": { "apps": [], "details": [ { "appIDs": ["TEAMID.app.revelio.Revelio"], "components": [ { "/": "/p/*", "comment": "Product preview deep link" } ] } ] },
//     "appclips":  { "apps": ["TEAMID.app.revelio.Revelio.Clip"] },
//     "webcredentials": { "apps": ["TEAMID.app.revelio.Revelio"] }
//   }
//
// TEAMID is a placeholder — the main session must swap it for the Apple
// Developer team ID once the cert is in place.

const IOS_BUNDLE_ID = 'app.revelio.Revelio';
const IOS_APPCLIP_BUNDLE_ID = 'app.revelio.Revelio.Clip';
const IOS_TEAM_ID_PLACEHOLDER = 'TEAMID';

const AASA_PAYLOAD = {
  applinks: {
    apps: [] as string[],
    details: [
      {
        appIDs: [`${IOS_TEAM_ID_PLACEHOLDER}.${IOS_BUNDLE_ID}`],
        components: [
          {
            '/': '/p/*',
            comment: 'Product preview deep link',
          },
        ],
      },
    ],
  },
  // appclips: per Apple, this MUST list the fully-qualified App Clip bundle
  // identifier (NOT the parent app's). iOS matches the invocation URL against
  // the parent's `applinks.components` path list to decide which /p/* URLs
  // launch the clip — so both stanzas share the same /p/* component set.
  appclips: {
    apps: [`${IOS_TEAM_ID_PLACEHOLDER}.${IOS_APPCLIP_BUNDLE_ID}`],
  },
  // webcredentials lets Password AutoFill share Keychain items between the
  // site and the app; harmless to include even if we never use it today.
  webcredentials: {
    apps: [`${IOS_TEAM_ID_PLACEHOLDER}.${IOS_BUNDLE_ID}`],
  },
};

wellKnownRouter.get('/apple-app-site-association', (_req, res) => {
  res.status(200);
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'public, max-age=3600');
  res.send(JSON.stringify(AASA_PAYLOAD));
});

// ─── Android App Links (Digital Asset Links) ──────────────────────────────────
// Android verifies deep links by fetching /.well-known/assetlinks.json. The
// fingerprint below is a placeholder; the main session must paste the real
// SHA-256 of the signing certificate (both upload & Play App Signing certs).
//
//   $ keytool -list -v -keystore release.keystore -alias revelio \
//       | grep SHA256

const ANDROID_PACKAGE = 'app.revelio';
const ANDROID_CERT_SHA256_PLACEHOLDER =
  'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA';

const ASSETLINKS_PAYLOAD = [
  {
    relation: [
      'delegate_permission/common.handle_all_urls',
      'delegate_permission/common.get_login_creds',
    ],
    target: {
      namespace: 'android_app',
      package_name: ANDROID_PACKAGE,
      sha256_cert_fingerprints: [ANDROID_CERT_SHA256_PLACEHOLDER],
    },
  },
];

wellKnownRouter.get('/assetlinks.json', (_req, res) => {
  res.status(200);
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'public, max-age=3600');
  res.send(JSON.stringify(ASSETLINKS_PAYLOAD));
});
