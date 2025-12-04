import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,          // 10 utilisateurs virtuels
  duration: '30s',  // pendant 30 secondes
};

export default function () {
  const res = http.get('http://10.0.2.15:8080/');
  check(res, {
    'status 200': (r) => r.status === 200,
  });
  sleep(1);
}
