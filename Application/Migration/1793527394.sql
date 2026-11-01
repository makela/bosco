-- Customers created from the admin UI were saved without reverse_name, so the
-- customer list (DISTINCT ON reverse_name) merged them all into one row.
UPDATE customers
SET reverse_name = lower(array_to_string(array_reverse(regexp_split_to_array(trim(name), '\s+')), ' '))
WHERE reverse_name = '' AND trim(name) <> '';
