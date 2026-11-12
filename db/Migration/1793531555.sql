-- Order lines keep the price they were ordered at, so later price changes
-- don't rewrite past invoices. The real historical prices are unknown, so
-- existing lines get the current product price (what invoices showed so far).
ALTER TABLE ordered_products ADD COLUMN unit_price INT DEFAULT NULL;
UPDATE ordered_products SET unit_price = products.price FROM products WHERE products.id = ordered_products.product_id;
ALTER TABLE ordered_products ALTER COLUMN unit_price SET NOT NULL;
