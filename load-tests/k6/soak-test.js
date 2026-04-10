/**
 * k6 Soak Test — sustained load over 30 minutes
 * Validates memory stability and no gradual degradation
 *
 * Usage:
 *   k6 run soak-test.js --env BASE_URL=http://backend-api:80
 */
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://backend-api.backend.svc.cluster.local';

export const options = {
  scenarios: {
    soak: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '5m',  target: 30 },   // Ramp to steady state
        { duration: '20m', target: 30 },   // Soak at steady load
        { duration: '5m',  target: 0  },   // Cool down
      ],
    },
  },
  thresholds: {
    'http_req_failed':         ['rate<0.01'],
    'http_req_duration{p:99}': ['p(99)<400'],
    'http_req_duration{p:95}': ['p(95)<250'],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}/api/health`, { timeout: '5s' });
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
