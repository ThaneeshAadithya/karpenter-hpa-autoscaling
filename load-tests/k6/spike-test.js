/**
 * k6 Spike Test — sudden extreme traffic spike
 * Simulates flash sale / viral event / DDoS mitigation test
 * 1 VU → 200 VU in 10 seconds — tests autoscaler reaction time
 *
 * Usage:
 *   k6 run spike-test.js --env BASE_URL=http://backend-api:80
 */
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://backend-api.backend.svc.cluster.local';

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 500,
      stages: [
        { duration: '1m',  target: 10  },  // Baseline: 10 RPS
        { duration: '10s', target: 200 },  // SPIKE: 200 RPS
        { duration: '3m',  target: 200 },  // Hold spike
        { duration: '30s', target: 10  },  // Drop back
        { duration: '2m',  target: 10  },  // Recovery
      ],
    },
  },
  thresholds: {
    // Allow higher error rate during initial spike (before HPA/Karpenter respond)
    'http_req_failed':         ['rate<0.05'],      // 5% tolerated during spike
    'http_req_duration{p:99}': ['p(99)<5000'],     // 5s max even during spike
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/api/products`, { timeout: '10s' });
  check(res, { 'not 5xx': (r) => r.status < 500 });
  sleep(0.1);
}
