# Recalls acceptance test

Apply migration `012_recalls.sql` against a clean database, then run these
steps end-to-end to verify the FDA recall pipeline. (1) Seed a user via
`INSERT INTO user_profiles (id, phone) VALUES ('11111111-1111-1111-1111-111111111111', '+15555550000')`
and a scan via `INSERT INTO scans (user_id, barcode, product_name, score, grade) VALUES ('11111111-1111-1111-1111-111111111111', '012345678901', 'Test Yogurt', 80, 'B')`.
(2) Seed a recall matching that UPC:
`INSERT INTO recalls (recall_number, classification, product_description, reason_for_recall, recalling_firm, product_type, upc_codes) VALUES ('F-TEST-001', 'Class I', 'Test Yogurt 32oz', 'Listeria contamination', 'Acme Foods', 'food', ARRAY['012345678901']) RETURNING id`.
(3) Invoke `matchAndNotify(<returned-id>)` from a Node REPL:
`node -e "require('ts-node/register'); require('./src/jobs/fdaRecalls').matchAndNotify('<id>').then(console.log)"`.
(4) Assert `SELECT * FROM recall_notifications WHERE user_id = '11111111-...'` returns exactly one row whose `barcode = '012345678901'` and `opened_at IS NULL`, and `SELECT * FROM push_outbox WHERE user_id = '11111111-...'` returns one row with `title = 'Product Recall Alert'` and a body containing "Acme Foods – Test Yogurt 32oz" and "Listeria contamination". (5) Re-run `matchAndNotify` with the same id and confirm no duplicate rows are created (ON CONFLICT DO NOTHING guard).
