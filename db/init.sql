CREATE TABLE inventario_producto (
    product_id BIGINT PRIMARY KEY,
    stock INTEGER NOT NULL,
    version BIGINT NOT NULL DEFAULT 0
);

-- 10.000 productos con stock inicial de 1000 unidades y version 0
INSERT INTO inventario_producto (product_id, stock, version)
SELECT generate_series(1, 10000), 1000, 0;
