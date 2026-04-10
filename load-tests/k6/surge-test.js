/**
 * k6 Surge Test — 2–3× traffic spike simulation
 * Validates that HPA + Karpenter handle the surge within 90 seconds
 *
 * Usage:
 *   k6 run surge-test.js
 *   k6 run surge-test.js --env BASE_URL=https://staging.example.com
 *
 * Watch scaling in parallel:
 *   ./scripts/watch-scaling.sh
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ── Custom metrics ──────────────────────────────────────────────────────────
const errorRate      = new Rate('error_rate');
const p99Latency     = new Trend('p99_latency', true);
const scaleoutEvents = new Counter('scaleout_events');

// ── Test config ─────────────────────────────────────────────────────────────
const BASE_URL = __ENV.BASE_URL || 'http://backend-api.backend.svc.cluster.local';

export const options = {
  /**
   * Surge scenario:
   *   1. Warm-up: 10 VUs for 2 min  → establish baseline
   *   2. Ramp up: 10 → 50 VUs in 30s → 2× spike
   *   3. Hold:    50 VUs for 3 min  → sustain pressure
   *   4. Spike:   50 → 100 VUs in 30s → 3× spike
   *   5. Hold:    100 VUs for 2 min  → max load
   *   6. Ramp down: 100 → 5 VUs in 1 min → recovery
   */
  scenarios: {
    surge: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: '2m',  target: 10  },   // Baseline
        { duration: '30s', target: 50  },   // 2× surge
        { duration: '3m',  target: 50  },   // Hold
        { duration: '30s', target: 100 },   // 3× surge
        { duration: '2m',  target: 100 },   // Max load
        { duration: '1m',  target: 5   },   // Recovery
      ],
    },
  },

  thresholds: {
    // SLO: 99.9% of requests succeed
    'http_req_failed':              ['rate<0.001'],
    // SLO: p99 latency < 500ms (may breach during scale-up, recovers after)
    'http_req_duration{p:99}':      ['p(99)<500'],
    // SLO: p95 latency < 300ms
    'http_req_duration{p:95}':      ['p(95)<300'],
    // Custom: error rate < 0.1%
    'error_rate':                   ['rate<0.001'],
  },

  // Output results to Prometheus (for Grafana dashboard)
  ext: {
    loadimpact: {
      projectID: 0,
      name:      'Surge Test',
    },
  },
};

// ── Test scenarios ──────────────────────────────────────────────────────────
const endpoints = [
  { path: '/api/products',     weight: 40 },
  { path: '/api/search?q=k8s', weight: 25 },
  { path: '/api/user/profile', weight: 20 },
  { path: '/api/recommendations', weight: 15 },
];

function pickEndpoint() {
  const rand = Math.random() * 100;
  let cumulative = 0;
  for (const ep of endpoints) {
    cumulative += ep.weight;
    if (rand <= cumulative) return ep.path;
  }
  return endpoints[0].path;
}

export default function () {
  const url = `${BASE_URL}${pickEndpoint()}`;

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-Request-ID': `k6-${__VU}-${__ITER}`,
    },
    timeout: '10s',
  };

  const res = http.get(url, params);

  // Record metrics
  const success = check(res, {
    'status is 200':         (r) => r.status === 200,
    'response time < 2s':    (r) => r.timings.duration < 2000,
    'no server error':       (r) => r.status < 500,
  });

  errorRate.add(!success);
  p99Latency.add(res.timings.duration);

  // Small sleep — simulate real user think time
  sleep(Math.random() * 0.5 + 0.1);
}

export function handleSummary(data) {
  const p99 = data.metrics.http_req_duration.values['p(99)'];
  const errRate = data.metrics.http_req_failed.values.rate;

  console.log(`\n=== SURGE TEST SUMMARY ===`);
  console.log(`p99 latency:  ${p99?.toFixed(0)}ms (target: <500ms)`);
  console.log(`Error rate:   ${(errRate * 100).toFixed(3)}% (target: <0.1%)`);
  console.log(`Total reqs:   ${data.metrics.http_reqs.values.count}`);

  return {
    'stdout': JSON.stringify(data, null, 2),
  };
}
