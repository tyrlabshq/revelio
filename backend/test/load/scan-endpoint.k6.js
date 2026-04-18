/**
 * k6 load test: GET /scan/:barcode
 *
 * Rotates through 20 common grocery/household barcodes and hammers the
 * scan endpoint at 100 VUs for 1 minute.
 *
 * Run with:
 *   k6 run backend/test/load/scan-endpoint.k6.js
 *
 * Override the host:
 *   k6 run -e API_BASE=https://api.revelio.app backend/test/load/scan-endpoint.k6.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';

const API_BASE = __ENV.API_BASE || 'http://localhost:8430';

// 20 real-world barcodes — Nutella, Cheerios, Coke, etc. Cache-hit bias
// is the point: this measures the hot-path performance, not OFF fetch.
const BARCODES = [
  '3017620422003', // Nutella 400g
  '0028400028509', // Cheetos Crunchy
  '0049000000443', // Coca-Cola 12oz can
  '0038000138416', // Cheerios
  '0038000200205', // Frosted Flakes
  '0028400589871', // Lay's Classic
  '0012000161155', // Mountain Dew
  '0044000030742', // Oreo Original
  '0036000291452', // Kleenex
  '0037000127024', // Tide Pods
  '0016000275287', // Nature Valley Granola
  '0030000010402', // Quaker Oats
  '0073762017028', // Skippy Peanut Butter
  '0068700000102', // Dawn Dish Soap
  '0021000658886', // Kraft Mac & Cheese
  '0025000057205', // Folgers Coffee
  '0051000012517', // Campbell's Chicken Noodle
  '0041800305216', // Goldfish Crackers
  '0031604018252', // Annie's Mac & Cheese
  '0041220823512', // Heinz Ketchup
];

export const options = {
  vus: 100,
  duration: '1m',
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<400'],
  },
};

export default function () {
  const barcode = BARCODES[Math.floor(Math.random() * BARCODES.length)];
  const res = http.get(`${API_BASE}/scan/${barcode}`, {
    tags: { name: 'scan_barcode' },
  });

  check(res, {
    'status is 200 or 404': r => r.status === 200 || r.status === 404,
    'responded under 1s': r => r.timings.duration < 1000,
  });

  sleep(0.1);
}
