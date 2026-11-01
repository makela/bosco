# Loads the schema into an empty database, for a new staging instance.
# Schema.sql already includes every migration, so they are all marked as
# applied. Does nothing when the database has tables, so it is safe to run
# before every migration.
#
# Reads DATABASE_URL, IHP_SCHEMA (IHP's own tables), APP_SCHEMA,
# IHP_MIGRATION_DIR and, optionally, APP_FIXTURES.

psql=(psql "$DATABASE_URL" --no-psqlrc --quiet -v ON_ERROR_STOP=1)

tables="$("${psql[@]}" --tuples-only --no-align \
    -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")"
if [ "$tables" != 0 ]; then
    echo "bootstrap-schema: the database has $tables tables already, nothing to do"
    exit 0
fi

echo "bootstrap-schema: loading the schema into an empty database"
{
    echo "BEGIN;"
    cat "$IHP_SCHEMA" "$APP_SCHEMA"
    if [ -n "${APP_FIXTURES:-}" ]; then
        # pg_dump wraps each table's rows in DISABLE/ENABLE TRIGGER ALL, which
        # only a superuser may run, and the database's owner isn't one. The
        # fixtures don't need it: their rows don't refer to each other.
        sed -E '/^ALTER TABLE .* (DISABLE|ENABLE) TRIGGER ALL;$/d' "$APP_FIXTURES"
    fi
    # Fixtures.sql empties search_path, so name the schema
    echo "CREATE TABLE IF NOT EXISTS public.schema_migrations (revision BIGINT NOT NULL UNIQUE);"
    for file in "$IHP_MIGRATION_DIR"/*.sql; do
        [ -e "$file" ] || continue
        revision="$(basename "$file" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')"
        if [ -n "$revision" ]; then
            echo "INSERT INTO public.schema_migrations (revision) VALUES ($revision);"
        fi
    done
    echo "COMMIT;"
} | "${psql[@]}"
