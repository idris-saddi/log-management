import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '2m', target: 10 }, // Ramp up to 10 users
    { duration: '5m', target: 10 }, // Stay at 10 users
    { duration: '2m', target: 20 }, // Ramp up to 20 users
    { duration: '5m', target: 20 }, // Stay at 20 users
    { duration: '2m', target: 0 },  // Ramp down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests should be below 500ms
    errors: ['rate<0.1'], // Error rate should be below 10%
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://service1:8081';

export default function() {
  const messages = [
    'UserLogin',
    'PaymentProcessed',
    'DatabaseQuery',
    'CacheHit',
    'APIRequest',
    'ServiceCall',
    'ErrorOccurred',
    'SystemHealth'
  ];
  
  const levels = ['INFO', 'WARN', 'ERROR', 'DEBUG'];
  
  const randomMessage = messages[Math.floor(Math.random() * messages.length)];
  const randomLevel = levels[Math.floor(Math.random() * levels.length)];
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };
  
  // Test log endpoint
  const logResponse = http.post(
    `${BASE_URL}/log?message=${randomMessage}&level=${randomLevel}`,
    null,
    params
  );
  
  check(logResponse, {
    'log endpoint status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  }) || errorRate.add(1);
  
  // Test health endpoint
  const healthResponse = http.get(`${BASE_URL}/actuator/health`);
  
  check(healthResponse, {
    'health endpoint status is 200': (r) => r.status === 200,
    'health response time < 200ms': (r) => r.timings.duration < 200,
  }) || errorRate.add(1);
  
  sleep(1);
}
