import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

// ---------------- Parametros (variables de entorno) ----------------
const STRATEGY    = (__ENV.STRATEGY || 'occ').toLowerCase();   // occ | occretry | pcc | none
const VUS         = parseInt(__ENV.VUS || '100');              // modelo cerrado (ramping-vus)
const RATE        = parseInt(__ENV.RATE || '0');               // >0: modelo abierto (req/s objetivo)
const RAMP        = __ENV.RAMP || '10s';
const HOLD        = __ENV.HOLD || '60s';
const DOWN        = __ENV.DOWN || '5s';
const TOTAL       = parseInt(__ENV.TOTAL_PRODUCTS || '10000');
const HOT         = parseInt(__ENV.HOT_PRODUCTS || '2000');    // tamano del conjunto caliente
const HOT_RATIO   = parseFloat(__ENV.HOT_RATIO || '0.8');      // fraccion de pedidos al conjunto caliente
const THINK_S     = parseFloat(__ENV.THINK_S || '0');          // pausa entre pedidos (solo modelo cerrado)
const BASE_URL    = __ENV.BASE_URL || 'http://localhost:8080';

const successCounter    = new Counter('app_success');
const conflictCounter   = new Counter('app_conflict');
const outOfStockCounter = new Counter('app_out_of_stock');
const errorCounter      = new Counter('app_error');

// 200/400/409 son respuestas esperadas del negocio; cualquier otra (500, etc.) cuenta como fallo.
http.setResponseCallback(http.expectedStatuses(200, 400, 409));

const stages = [
    { duration: RAMP, target: RATE > 0 ? RATE : VUS },
    { duration: HOLD, target: RATE > 0 ? RATE : VUS },
    { duration: DOWN, target: 0 },
];

export const options = RATE > 0
    ? {
        scenarios: {
            main: {
                executor: 'ramping-arrival-rate',
                startRate: 1,
                timeUnit: '1s',
                preAllocatedVUs: parseInt(__ENV.PREALLOC || '300'),
                maxVUs: parseInt(__ENV.MAXVUS || '3000'),
                stages: stages,
            },
        },
    }
    : {
        scenarios: {
            main: {
                executor: 'ramping-vus',
                startVUs: 0,
                stages: stages,
                gracefulRampDown: '30s',
                gracefulStop: '30s',
            },
        },
    };

// Asegura que los 4 contadores existan en el resumen aunque valgan 0.
export function setup() {
    successCounter.add(0);
    conflictCounter.add(0);
    outOfStockCounter.add(0);
    errorCounter.add(0);
}

function getProductId() {
    if (TOTAL <= HOT || Math.random() < HOT_RATIO) {
        return Math.floor(Math.random() * Math.min(HOT, TOTAL)) + 1;
    }
    return HOT + Math.floor(Math.random() * (TOTAL - HOT)) + 1;
}

const params = { headers: { 'Content-Type': 'application/json' } };

export default function () {
    const url = `${BASE_URL}/inventory/purchase/${STRATEGY}`;
    const payload = JSON.stringify({ productId: getProductId(), quantity: 1 });
    const res = http.post(url, payload, params);

    if (res.status === 200) {
        successCounter.add(1);
    } else if (res.status === 409) {
        conflictCounter.add(1);
    } else if (res.status === 400) {
        outOfStockCounter.add(1);
    } else {
        errorCounter.add(1);
    }

    check(res, { 'respuesta esperada (200/400/409)': (r) => [200, 400, 409].includes(r.status) });

    if (THINK_S > 0 && RATE === 0) {
        sleep(THINK_S);
    }
}
