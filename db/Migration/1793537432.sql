-- array_reverse() was a helper for migration 1759991022's one-off update and
-- nothing uses it since, so the database matches Schema.sql again. In public:
-- since PostgreSQL 18, a bare array_reverse is the built-in pg_catalog one.
DROP FUNCTION IF EXISTS public.array_reverse(anyarray);
