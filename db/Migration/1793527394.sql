-- Customers created from the admin UI were saved without reverse_name, so the
-- customer list (DISTINCT ON reverse_name) merged them all into one row.
UPDATE customers
SET reverse_name = (
    SELECT lower(string_agg(word, ' ' ORDER BY position DESC))
    FROM unnest(regexp_split_to_array(trim(name), '\s+')) WITH ORDINALITY AS words(word, position)
)
WHERE reverse_name = '' AND trim(name) <> '';
