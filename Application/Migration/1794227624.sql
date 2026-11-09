-- Splits a customer's name into first and last name and the address into
-- street address, postal code and city. The code no longer uses name and
-- address; they stay, with what customers wrote, for a release in case the
-- split needs fixing, and a later migration drops them. reverse_name, the
-- sort key, is now made of the last and first name.
--
-- Text is handled with the Finnish ICU collation ("fi-x-icu"), so that ä, ö
-- and å are letters and change case whatever locale the database was created
-- with: with the C locale initcap('BILLNÄS') would be 'BillnÄS'.
--
-- The rules follow scripts/profile-customers.sql's results from production
-- (833 customers, November 2026); scripts/check-customer-split.sql lists what
-- is left to fix by hand.
ALTER TABLE customers
    ADD COLUMN first_name TEXT DEFAULT '' NOT NULL,
    ADD COLUMN last_name TEXT DEFAULT '' NOT NULL,
    ADD COLUMN street_address TEXT DEFAULT '' NOT NULL,
    ADD COLUMN postal_code TEXT DEFAULT '' NOT NULL,
    ADD COLUMN city TEXT DEFAULT '' NOT NULL,
    ALTER COLUMN name SET DEFAULT '';

-- The last word is the last name, the words before it the first name; a
-- one-word name goes to first_name. A first or last name written all in lower
-- or upper case gets capitalised: "anna-liisa mäki" is "Anna-Liisa Mäki",
-- "Matti VIRTANEN" "Matti Virtanen".
UPDATE customers
SET first_name = CASE WHEN f = lower(f) OR f = upper(f) THEN initcap(f) ELSE f END,
    last_name = CASE WHEN l = lower(l) OR l = upper(l) THEN initcap(l) ELSE l END
FROM (
    SELECT id,
        CASE WHEN n ~ ' ' THEN regexp_replace(n, ' [^ ]+$', '') ELSE n END AS f,
        CASE WHEN n ~ ' ' THEN substring(n FROM '[^ ]+$') ELSE '' END AS l
    FROM (SELECT id, regexp_replace(btrim(name), '\s+', ' ', 'g') COLLATE "fi-x-icu" AS n FROM customers) t
) s
WHERE customers.id = s.id;

-- An address is tried against these, in order, after a trailing ", Finland"
-- or "Suomi" is dropped. FI- before a postal code is dropped too.
--   1. street[,] 00100[,] City
--   2. street City 00100          (city before the postal code)
--   3. street[,] 00100            (no city)
--   4. street, City               (no postal code)
-- One that matches none of them stays whole in street_address, postal code
-- and city empty: most of those are just a street.
UPDATE customers
SET street_address = regexp_replace(coalesce(p[1], a), '\s+', ' ', 'g'),
    postal_code = coalesce(p[2], ''),
    city = coalesce(p[3], '')
FROM (
    SELECT id, a,
        coalesce(
            regexp_match(a, '^(.*[^,[:space:]])[,[:space:]]+(?:FI-?[[:space:]]*)?([0-9]{5})[,[:space:]]+([^0-9[:space:],][^0-9]*)$', 'i'),
            (SELECT ARRAY[m[1], m[3], m[2]]
             FROM regexp_match(a, '^(.*[0-9][[:alpha:]]?)[,[:space:]]+([[:alpha:]][^0-9,]*[[:alpha:]])[,[:space:]]+(?:FI-?)?([0-9]{5})$', 'i') AS m
             WHERE m IS NOT NULL),
            regexp_match(a, '^(.*[^,[:space:]])[,[:space:]]+(?:FI-?[[:space:]]*)?([0-9]{5})()$', 'i'),
            (SELECT ARRAY[m[1], '', m[2]]
             FROM regexp_match(a, '^(.*[0-9][[:alpha:]]?)[[:space:]]*,[[:space:]]*([[:alpha:]][^0-9,]*[[:alpha:]])$') AS m
             WHERE m IS NOT NULL)
        ) AS p
    FROM (
        SELECT id,
            regexp_replace(btrim(address, E' \t\r\n') COLLATE "fi-x-icu", '[,[:space:]]*(Finland|Suomi)\.?$', '', 'i') AS a
        FROM customers
    ) t
) s
WHERE customers.id = s.id;

-- Cities: "HELSINKI" is "Helsinki", and the common Helsinki abbreviation and
-- misspelling are Helsinki.
UPDATE customers
SET city = CASE
        WHEN lower(c) IN ('hki', 'hesinki') THEN 'Helsinki'
        WHEN c = upper(c) THEN initcap(c)
        ELSE c
    END
FROM (SELECT id, btrim(regexp_replace(city, '\s+', ' ', 'g')) COLLATE "fi-x-icu" AS c FROM customers) s
WHERE customers.id = s.id AND customers.city <> '';

-- "virtanen maija", as reverseNameOf in Application/Customer.hs
UPDATE customers
SET reverse_name = lower(btrim(regexp_replace(last_name || ' ' || first_name, '\s+', ' ', 'g')) COLLATE "fi-x-icu");
