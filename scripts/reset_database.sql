-- Restaurar el stock y la versión de todos los productos
-- al estado inicial del experimento.

UPDATE inventario_producto
SET stock = 1000,
    version = 0;