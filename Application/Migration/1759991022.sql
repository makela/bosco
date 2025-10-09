ALTER TABLE customers ADD COLUMN reverse_name TEXT DEFAULT '' NOT NULL;
CREATE OR REPLACE FUNCTION array_reverse(anyarray)
RETURNS anyarray LANGUAGE SQL AS $$
  SELECT array_agg(val ORDER BY idx DESC)
  FROM unnest($1) WITH ORDINALITY AS t(val, idx);
$$;
update customers set reverse_name = lower(array_to_string(array_reverse(string_to_array(name, ' ')), ' '));
