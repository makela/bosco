-- What the migration that splits customers' names and addresses (1794227624)
-- left behind, on a database it has run on, e.g. staging with a copy of
-- production:
--
--   sudo -u bosco_staging psql bosco_staging < check-customer-split.sql
--
-- It only reads. Like profile-customers.sql it prints counts and shapes, not
-- names or addresses, except cities that at least three customers share. The
-- last part lists the ids of the customers to check by hand in the admin
-- (/admin/ShowCustomer?customerId=<id>), customers with orders first.

\set ON_ERROR_STOP on
\pset footer off

CREATE FUNCTION pg_temp.shape(t text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(string_agg(
        CASE
            WHEN tok ~ '^[0-9]+$' THEN repeat('9', length(tok))
            WHEN tok ~ '^[[:upper:]]$' THEN 'A'
            WHEN tok ~ '^[[:lower:]]$' THEN 'a'
            WHEN tok ~ '^[[:upper:]][[:lower:]]+$' THEN 'Aa'
            WHEN tok ~ '^[[:upper:]]+$' THEN 'AA'
            WHEN tok ~ '^[[:lower:]]+$' THEN 'aa'
            WHEN tok ~ '^[[:alpha:]]+$' THEN 'aA'
            WHEN tok ~ '\n' THEN '⏎'
            WHEN tok ~ '^\s$' THEN ' '
            WHEN tok ~ '^\s+$' THEN '␣␣'
            ELSE tok
        END, '' ORDER BY n), '')
    FROM regexp_matches(t COLLATE "fi-x-icu", '[0-9]+|[[:alpha:]]+|\s+|.', 'g') WITH ORDINALITY AS m(tok_, n),
         LATERAL (SELECT tok_[1] COLLATE "fi-x-icu" AS tok) x
$$;

-- The checks below use the Finnish ICU collation, so that ä, ö and å are
-- letters whatever locale the database was created with.
CREATE TEMP VIEW c AS
SELECT customers.*,
    EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = customers.id) AS has_orders,
    concat_ws(', ',
        CASE WHEN last_name = '' THEN 'one-word name' END,
        CASE WHEN first_name ~ ' ' AND first_name COLLATE "fi-x-icu" !~ '^[[:upper:]][[:alpha:]-]* [[:upper:]][[:alpha:]-]*$' THEN 'unusual name' END,
        CASE WHEN (first_name || last_name) COLLATE "fi-x-icu" ~ '[^[:alpha:] .''-]' THEN 'name has digits or punctuation' END,
        CASE WHEN address <> '' AND postal_code = '' AND city = '' THEN 'street only' END,
        CASE WHEN postal_code <> '' AND city = '' THEN 'no city' END,
        CASE WHEN postal_code = '' AND city <> '' THEN 'no postal code' END,
        CASE WHEN street_address <> '' AND street_address !~ '[0-9]' THEN 'street without number' END,
        CASE WHEN street_address ~ ',' THEN 'comma in street' END,
        CASE WHEN city COLLATE "fi-x-icu" ~ '[^[:alpha:] -]' OR city ~ ' ' THEN 'unusual city' END
    ) AS issues
FROM customers;

\echo
\echo '== Name shapes after the split (first | last)'
SELECT pg_temp.shape(first_name) || ' | ' || pg_temp.shape(last_name) AS shape, count(*) AS customers
FROM c GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 30;

\echo
\echo '== Address shapes after the split (street | postal code | city)'
SELECT pg_temp.shape(street_address) || ' | ' || pg_temp.shape(postal_code) || ' | ' || pg_temp.shape(city) AS shape,
    count(*) AS customers
FROM c WHERE address <> '' GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 40;

\echo
\echo '== Cities (three or more customers; the rest counted)'
WITH cities AS (SELECT city, count(*) AS customers FROM c WHERE city <> '' GROUP BY 1)
SELECT city, customers FROM cities WHERE customers >= 3
UNION ALL
SELECT '(' || count(*) || ' others)', coalesce(sum(customers), 0) FROM cities WHERE customers < 3
ORDER BY 2 DESC, 1;

\echo
\echo '== What to check by hand'
SELECT issue, count(*) AS customers, count(*) FILTER (WHERE has_orders) AS with_orders
FROM c, unnest(string_to_array(issues, ', ')) AS issue
GROUP BY 1 ORDER BY 2 DESC;

\echo
\echo '== Customers to check, with orders first'
SELECT id, has_orders, issues FROM c WHERE issues <> ''
ORDER BY has_orders DESC, issues = 'street only', issues, id;
