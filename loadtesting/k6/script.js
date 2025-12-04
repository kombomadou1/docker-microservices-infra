import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,          // 10 utilisateurs virtuels
  duration: '30s',  // pendant 30 secondes
};
//http://148.60.11.119:3000/
export default function () {
  const res = http.get('http://tpdocker:boomerboom@wiki.tpdocker.istic.univ-rennes1.fr/');
  check(res, {
    'status 200': (r) => r.status === 200,
  });
  sleep(1);
}
