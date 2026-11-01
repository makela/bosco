-- array_reverse() was a helper for migration 1759991022's one-off update and
-- nothing uses it since, so the database matches Schema.sql again.
DROP FUNCTION IF EXISTS array_reverse(anyarray);
