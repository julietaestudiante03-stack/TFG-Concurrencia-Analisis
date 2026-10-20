package com.tfg.concurrencia;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/inventory")
public class InventoryController {

    /** Reintentos máximos de la variante occretry (4 intentos en total). */
    private static final int MAX_RETRIES = 3;

    private final InventoryService service;
    private final StatsRegistry stats;

    public InventoryController(InventoryService service, StatsRegistry stats) {
        this.service = service;
        this.stats = stats;
    }

    /** strategy = occ | occretry | pcc | none */
    @PostMapping("/purchase/{strategy}")
    public ResponseEntity<PurchaseResponse> purchase(@PathVariable String strategy,
                                                     @RequestBody PurchaseRequest request) {
        long productId = request.getProductId();
        int qty = request.getQuantity();
        try {
            String result;
            switch (strategy) {
                case "occ":
                    result = service.purchaseOCC(productId, qty);
                    if ("CONFLICT".equals(result)) stats.conflictAttempt();
                    break;
                case "occretry":
                    result = service.purchaseOCC(productId, qty);
                    int attempts = 0;
                    while ("CONFLICT".equals(result)) {
                        stats.conflictAttempt();
                        if (attempts >= MAX_RETRIES) break;
                        attempts++;
                        stats.retry();
                        result = service.purchaseOCC(productId, qty);
                    }
                    break;
                case "pcc":
                    result = service.purchasePCC(productId, qty);
                    break;
                case "none":
                    result = service.purchaseNONE(productId, qty);
                    break;
                default:
                    return ResponseEntity.status(HttpStatus.NOT_FOUND)
                            .body(new PurchaseResponse(false, "UNKNOWN_STRATEGY"));
            }
            return handle(result, productId);
        } catch (Exception e) {
            // Deadlocks (SQLState 40P01), timeouts del pool, conexiones agotadas, etc.
            stats.error(e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(new PurchaseResponse(false, "ERROR"));
        }
    }

    private ResponseEntity<PurchaseResponse> handle(String result, long productId) {
        switch (result) {
            case "SUCCESS":
                stats.success(productId);
                return ResponseEntity.ok(new PurchaseResponse(true, "SUCCESS"));
            case "CONFLICT":
                stats.conflictReturned();
                return ResponseEntity.status(HttpStatus.CONFLICT).body(new PurchaseResponse(false, "CONFLICT"));
            case "OUT_OF_STOCK":
                stats.outOfStock();
                return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(new PurchaseResponse(false, "OUT_OF_STOCK"));
            default:
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(new PurchaseResponse(false, "UNKNOWN"));
        }
    }

    @GetMapping("/stats")
    public Map<String, Object> stats() { return stats.snapshot(); }

    @PostMapping("/stats/reset")
    public Map<String, Object> reset() { stats.reset(); return stats.snapshot(); }

    @GetMapping("/audit")
    public Map<String, Object> audit(@RequestParam int initialStock) { return service.audit(initialStock); }
}
