package com.tfg.concurrencia;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class InventoryService {

    private final JdbcTemplate jdbc;
    private final StatsRegistry stats;

    public InventoryService(JdbcTemplate jdbc, StatsRegistry stats) {
        this.jdbc = jdbc;
        this.stats = stats;
    }

    // ESTRATEGIA 1: OCC. Un intento: lee stock+version y actualiza solo si la versión no cambió.
    // Es transaccional (igual que PCC) para que ambas tengan el mismo costo base de BEGIN/COMMIT.
    @Transactional
    public String purchaseOCC(Long productId, Integer quantity) {
        Map<String, Object> row = jdbc.queryForMap(
                "SELECT stock, version FROM inventario_producto WHERE product_id = ?", productId);
        int stock = ((Number) row.get("stock")).intValue();
        long version = ((Number) row.get("version")).longValue();

        if (stock < quantity) {
            return "OUT_OF_STOCK";
        }
        int rows = jdbc.update(
                "UPDATE inventario_producto SET stock = stock - ?, version = version + 1 " +
                "WHERE product_id = ? AND version = ?", quantity, productId, version);
        return rows == 0 ? "CONFLICT" : "SUCCESS";
    }

    // ESTRATEGIA 2: PCC. SELECT ... FOR UPDATE + UPDATE en la misma transacción.
    // También incrementa version para poder auditar igual que en OCC.
    @Transactional
    public String purchasePCC(Long productId, Integer quantity) {
        Integer stock = jdbc.queryForObject(
                "SELECT stock FROM inventario_producto WHERE product_id = ? FOR UPDATE", Integer.class, productId);
        if (stock == null || stock < quantity) {
            return "OUT_OF_STOCK";
        }
        jdbc.update(
                "UPDATE inventario_producto SET stock = stock - ?, version = version + 1 WHERE product_id = ?",
                quantity, productId);
        return "SUCCESS";
    }

    // CONTROL POSITIVO (NONE): sin control de concurrencia (lectura + escritura de valor ABSOLUTO).
    // Produce "lost updates" a propósito para demostrar que la auditoría SÍ detecta inconsistencias.
    // Es un instrumento de validación, no una alternativa real.
    public String purchaseNONE(Long productId, Integer quantity) {
        Integer stock = jdbc.queryForObject(
                "SELECT stock FROM inventario_producto WHERE product_id = ?", Integer.class, productId);
        if (stock == null || stock < quantity) {
            return "OUT_OF_STOCK";
        }
        jdbc.update(
                "UPDATE inventario_producto SET stock = ?, version = version + 1 WHERE product_id = ?",
                stock - quantity, productId);
        return "SUCCESS";
    }

    // AUDITORÍA por producto: compara lo que la aplicación confirmó (ventas OK) con lo que quedó
    // realmente en la base. Es evidencia independiente de k6.
    public Map<String, Object> audit(int initialStock) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT product_id, stock, version FROM inventario_producto");

        long totalSuccessApp = 0, totalSoldDb = 0, sumVersion = 0;
        long lostUnits = 0, oversoldUnits = 0;
        int productsLost = 0, productsOversold = 0, productsNegative = 0, productsVersionMismatch = 0;
        int minStock = Integer.MAX_VALUE;
        int productsTouched = 0;

        for (Map<String, Object> r : rows) {
            long id = ((Number) r.get("product_id")).longValue();
            int stock = ((Number) r.get("stock")).intValue();
            long version = ((Number) r.get("version")).longValue();

            long soldDb = (long) initialStock - stock;   // unidades que salieron según la BD
            long succApp = stats.successOf(id);          // ventas confirmadas por la aplicación

            totalSoldDb += soldDb;
            totalSuccessApp += succApp;
            sumVersion += version;
            if (stock < minStock) minStock = stock;
            if (succApp > 0 || soldDb != 0) productsTouched++;

            if (succApp > soldDb) {                      // la app confirmó más de lo que la BD descontó
                productsLost++;
                lostUnits += (succApp - soldDb);
            }
            if (succApp > initialStock) {                // vendió más unidades que las existentes
                productsOversold++;
                oversoldUnits += (succApp - initialStock);
            }
            if (stock < 0) productsNegative++;
            if (version != succApp) productsVersionMismatch++;
        }

        boolean consistent = lostUnits == 0 && oversoldUnits == 0 && productsNegative == 0
                && totalSoldDb == totalSuccessApp && sumVersion == totalSuccessApp;

        Map<String, Object> m = new LinkedHashMap<>();
        m.put("initial_stock", initialStock);
        m.put("products", rows.size());
        m.put("products_touched", productsTouched);
        m.put("total_success_app", totalSuccessApp);
        m.put("total_sold_db", totalSoldDb);
        m.put("sum_version", sumVersion);
        m.put("lost_update_units", lostUnits);
        m.put("products_with_lost_updates", productsLost);
        m.put("oversold_units", oversoldUnits);
        m.put("products_oversold", productsOversold);
        m.put("products_negative_stock", productsNegative);
        m.put("products_version_mismatch", productsVersionMismatch);
        m.put("min_stock", rows.isEmpty() ? 0 : minStock);
        m.put("consistent", consistent);
        return m;
    }
}
