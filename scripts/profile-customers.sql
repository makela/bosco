-- How customers' names and addresses are written, before they are split into
-- first_name/last_name and street_address/postal_code/city.
--
--   sudo -u bosco_fi psql bosco_fi < profile-customers.sql
--
-- It only reads. It prints counts and "shapes", never a name or an address: in
-- a shape every word becomes Aa (capitalised), aa, AA, A (single letter) or aA
-- (mixed case), every digit 9, and a line break ⏎; punctuation stays. So
-- "Testikatu 12 B 4, 00100 Helsinki" is "Aa 99 A 9, 99999 Aa". Cities are
-- listed only when at least three customers share one.
--
-- The rules checked below are the ones the backfill migration uses:
-- * name: the last word is the last name, the words before it the first name;
-- * address: "<street>[,] [FI-]<5 digits> <city>", whitespace or a comma
--   (or a line break) between street and postal code.

\set ON_ERROR_STOP on
\pset footer off

-- Letters are recognised by the database's ctype; with a C ctype "ä" would not
-- be a letter and would show up as itself in the shapes.
SELECT datctype FROM pg_database WHERE datname = current_database();

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
            WHEN tok ~ '^\s+$' THEN '␣␣'   -- several spaces or a tab
            ELSE tok
        END, '' ORDER BY n), '')
    FROM regexp_matches(t, '[0-9]+|[[:alpha:]]+|\s+|.', 'g') WITH ORDINALITY AS m(tok_, n),
         LATERAL (SELECT tok_[1] AS tok) x
$$;

CREATE TEMP VIEW c AS
SELECT
    id,
    name,
    trim(name) AS tname,
    cardinality(regexp_split_to_array(trim(name), '\s+')) AS name_words,
    address,
    btrim(address, E' \t\r\n') AS taddress,
    EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = customers.id) AS has_orders
FROM customers;

CREATE TEMP VIEW addr AS
SELECT
    c.*,
    m[1] AS street,
    m[2] AS postal_code,
    m[3] AS city
FROM c
LEFT JOIN LATERAL (
    SELECT regexp_match(taddress, '^(.*[^,[:space:]])[,[:space:]]+(?:FI-?[[:space:]]*)?([0-9]{5})[[:space:]]+([^0-9[:space:]].*)$', 'i') AS m
) r ON true;

\echo
\echo '== Totals'
SELECT
    count(*) AS customers,
    count(*) FILTER (WHERE has_orders) AS with_orders,
    count(*) FILTER (WHERE tname = '') AS empty_name,
    count(*) FILTER (WHERE taddress = '') AS empty_address
FROM c;

\echo
\echo '== Words in name (the last word becomes the last name)'
SELECT name_words AS words, count(*) AS customers
FROM c WHERE tname <> '' GROUP BY 1 ORDER BY 1;

\echo
\echo '== Names the last-word rule probably gets wrong (a name can be in several)'
SELECT
    count(*) FILTER (WHERE name_words = 1) AS one_word,
    count(*) FILTER (WHERE name_words > 2) AS three_or_more_words,
    count(*) FILTER (WHERE tname LIKE '%,%') AS comma,
    count(*) FILTER (WHERE tname ~* '(^|\s)(ja|och|and|et)(\s|$)|&|/|\+') AS couple_or_several,
    count(*) FILTER (WHERE tname ~* '(^|[\s.,])(oy|oyj|ab|ky|ay|tmi|ry|osk|ltd|inc|gmbh|sarl|sas)(\.|\s|$)') AS company,
    count(*) FILTER (WHERE tname ~ '[0-9]') AS digits,
    count(*) FILTER (WHERE tname ~ '\.') AS dot_or_initial,
    count(*) FILTER (WHERE tname ~ '[[:alpha:]]' AND tname = upper(tname)) AS all_caps,
    count(*) FILTER (WHERE tname ~ '[[:alpha:]]' AND tname = lower(tname)) AS all_lower,
    count(*) FILTER (WHERE name <> tname OR name ~ '\s\s') AS extra_spaces
FROM c;

\echo
\echo '== Name shapes (Aa = capitalised word), most common first'
SELECT pg_temp.shape(name) AS shape, count(*) AS customers
FROM c GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 40;

\echo
\echo '== Addresses by how the street/postal code/city rule handles them'
SELECT
    CASE
        WHEN taddress = '' THEN '1 empty'
        WHEN street IS NOT NULL THEN '2 splits'
        WHEN taddress ~ '^(FI-?\s*)?[0-9]{5}\s' THEN '3 starts with a postal code'
        WHEN taddress ~ '(^|[^0-9])[0-9]{5}([^0-9]|$)' THEN '4 has a postal code elsewhere'
        ELSE '5 no postal code'
    END AS outcome,
    count(*) AS customers,
    count(*) FILTER (WHERE has_orders) AS with_orders
FROM addr GROUP BY 1 ORDER BY 1;

\echo
\echo '== Shapes of the addresses that do not split'
SELECT pg_temp.shape(address) AS shape, count(*) AS customers
FROM addr WHERE street IS NULL AND taddress <> ''
GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 40;

\echo
\echo '== Shapes of the addresses that split, most common first'
SELECT pg_temp.shape(address) AS shape, count(*) AS customers
FROM addr WHERE street IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC, 1 LIMIT 40;

\echo
\echo '== Split addresses worth a second look'
SELECT
    count(*) FILTER (WHERE street !~ '[0-9]') AS street_without_number,
    count(*) FILTER (WHERE street ~ '[,\n]') AS street_with_comma_or_line_break,
    count(*) FILTER (WHERE city ~ '[0-9,]') AS city_with_digit_or_comma,
    count(*) FILTER (WHERE city ~ '\s') AS city_of_several_words,
    count(*) FILTER (WHERE city = upper(city)) AS city_all_caps,
    count(*) FILTER (WHERE taddress ~* 'FI-?\s*[0-9]{5}') AS fi_prefix,
    count(*) FILTER (WHERE taddress ~* '(^|\s)(PL|PO Box|c/o)(\s|$)') AS po_box_or_c_o
FROM addr WHERE street IS NOT NULL;

\echo
\echo '== Cities after the split (three or more customers; the rest counted)'
WITH cities AS (
    SELECT city, count(*) AS customers FROM addr WHERE city IS NOT NULL GROUP BY 1
)
SELECT city, customers FROM cities WHERE customers >= 3
UNION ALL
SELECT '(' || count(*) || ' other spellings)', coalesce(sum(customers), 0) FROM cities WHERE customers < 3
ORDER BY 2 DESC, 1;

\echo
\echo '== Duplicate customers (same name and address ignoring case and spaces)'
SELECT count(*) AS groups, coalesce(sum(n), 0) AS customers
FROM (
    SELECT count(*) AS n
    FROM c
    GROUP BY lower(regexp_replace(tname, '\s+', ' ', 'g')),
             lower(regexp_replace(taddress, '[\s,]+', ' ', 'g'))
    HAVING count(*) > 1
) d;
