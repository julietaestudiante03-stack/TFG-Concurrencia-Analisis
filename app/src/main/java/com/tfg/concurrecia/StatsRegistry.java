package com.tfg.concurrencia;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.LongAdder;

/**
 * Contadores internos de la aplicación (Campaña B).
 * Miden lo que k6 no ve: conflictos internos, reintentos, tipos de error y,
 * sobre todo, cuántas ventas confirmó la aplicación POR PRODUCTO (insumo de la auditoría).
 */
@Component
public class StatsRegistry {

    private final ConcurrentHashMap<Long, LongAdder> successByProduct = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, LongAdder> errorsByType = new ConcurrentHashMap<>();
    private final LongAdder conflictsInternal = new LongAdder(); // CONFLICT de cada intento OCC
    private final LongAdder retries = new LongAdder();           // intentos adicionales (occretry)
    private final LongAdder conflictsReturned = new LongAdder(); // 409 devueltos al cliente
    private final LongAdder outOfStock = new LongAdder();
    private final LongAdder errors = new LongAdder();
    private final List<String> firstErrors = new ArrayList<>();

    public void success(long productId) {
        successByProduct.computeIfAbsent(productId, k -> new LongAdder()).increment();
    }

    public void conflictAttempt() { conflictsInternal.increment(); }
    public void retry() { retries.increment(); }
    public void conflictReturned() { conflictsReturned.increment(); }
    public void outOfStock() { outOfStock.increment(); }

    public void error(Exception e) {
        errors.increment();
        errorsByType.computeIfAbsent(e.getClass().getSimpleName(), k -> new LongAdder()).increment();
        synchronized (firstErrors) {
            if (firstErrors.size() < 20) {
                String msg = String.valueOf(e.getMessage());
                firstErrors.add(e.getClass().getSimpleName() + ": " + (msg.length() > 300 ? msg.substring(0, 300) : msg));
            }
        }
    }

    public long successOf(long productId) {
        LongAdder a = successByProduct.get(productId);
        return a == null ? 0L : a.sum();
    }

    public long totalSuccess() {
        long t = 0;
        for (LongAdder a : successByProduct.values()) t += a.sum();
        return t;
    }

    public void reset() {
        successByProduct.clear();
        errorsByType.clear();
        conflictsInternal.reset();
        retries.reset();
        conflictsReturned.reset();
        outOfStock.reset();
        errors.reset();
        synchronized (firstErrors) { firstErrors.clear(); }
    }

    public Map<String, Object> snapshot() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("success_total", totalSuccess());
        m.put("conflicts_internal_attempts", conflictsInternal.sum());
        m.put("retries", retries.sum());
        m.put("conflicts_returned", conflictsReturned.sum());
        m.put("out_of_stock", outOfStock.sum());
        m.put("errors", errors.sum());
        Map<String, Long> byType = new LinkedHashMap<>();
        errorsByType.forEach((k, v) -> byType.put(k, v.sum()));
        m.put("errors_by_type", byType);
        synchronized (firstErrors) { m.put("first_errors", new ArrayList<>(firstErrors)); }
        return m;
    }
}
