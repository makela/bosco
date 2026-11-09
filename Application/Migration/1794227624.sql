-- DRAFT: the rules below wait for scripts/profile-customers.sql's results
-- from production.
--
-- Splits a customer's name into first and last name and the address into
-- street address, postal code and city. The old name, address and
-- reverse_name stay until the code no longer uses them; a later migration
-- drops them.
ALTER TABLE customers
    ADD COLUMN first_name TEXT DEFAULT '' NOT NULL,
    ADD COLUMN last_name TEXT DEFAULT '' NOT NULL,
    ADD COLUMN street_address TEXT DEFAULT '' NOT NULL,
    ADD COLUMN postal_code TEXT DEFAULT '' NOT NULL,
    ADD COLUMN city TEXT DEFAULT '' NOT NULL;

-- The last word is the last name, the words before it the first name. A
-- one-word name goes to first_name.
UPDATE customers
SET first_name = CASE WHEN n ~ ' ' THEN regexp_replace(n, ' \S+$', '') ELSE n END,
    last_name = CASE WHEN n ~ ' ' THEN substring(n FROM '\S+$') ELSE '' END
FROM (SELECT id, regexp_replace(btrim(name), '\s+', ' ', 'g') AS n FROM customers) s
WHERE customers.id = s.id;

-- "<street>[,] [FI-]<5 digits> <city>". An address that doesn't match stays
-- whole in street_address, with postal code and city empty, to fix by hand.
UPDATE customers
SET street_address = coalesce(m[1], a),
    postal_code = coalesce(m[2], ''),
    city = coalesce(m[3], '')
FROM (
    SELECT id, a,
        regexp_match(a, '^(.*[^,[:space:]])[,[:space:]]+(?:FI-?[[:space:]]*)?([0-9]{5})[[:space:]]+([^0-9[:space:]].*)$', 'i') AS m
    FROM (SELECT id, btrim(address, E' \t\r\n') AS a FROM customers) t
) s
WHERE customers.id = s.id;
