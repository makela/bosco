# Runs the deployment's database steps against a temporary PostgreSQL, with
# IHP's migrate program and bootstrap-schema as the NixOS module runs them:
#
# - a new staging database gets the schema, the fixtures and every migration
# - production, at the schema of migration 1760540031 with some data, gets the
#   newer migrations with minimumRevision, and ends up matching Schema.sql
{
  pkgs,
  migrate,
  bootstrapSchema,
  src,
  ihpSchema,
}:
pkgs.runCommand "deploy-migration-tests"
  {
    nativeBuildInputs = [
      pkgs.postgresql
      migrate
      bootstrapSchema
      pkgs.diffutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    export PGDATA="$TMPDIR/pgdata" PGHOST="$TMPDIR/pghost"
    mkdir -p "$PGHOST"
    initdb -D "$PGDATA" --no-locale --encoding=UTF8 >/dev/null
    echo "unix_socket_directories = '$PGHOST'" >> "$PGDATA/postgresql.conf"
    echo "listen_addresses = '''" >> "$PGDATA/postgresql.conf"
    pg_ctl -D "$PGDATA" -l "$TMPDIR/postgres.log" -w start >/dev/null
    trap 'pg_ctl -D "$PGDATA" stop -m fast >/dev/null' EXIT

    export IHP_SCHEMA=${ihpSchema}
    export APP_SCHEMA=${src}/Application/Schema.sql
    export APP_FIXTURES=${src}/Application/Fixtures.sql
    export IHP_MIGRATION_DIR=${src}/Application/Migration/
    # Production's last migration before the NixOS deployment, as in the README
    minimumRevision=1760540031

    # The database $1, as the role $2 or else as the sandbox's superuser
    url() { echo "postgresql:///$1?host=$PGHOST''${2:+&user=$2}"; }
    # Like the NixOS module: an ordinary role owning the database of its name
    ownedDatabase() {
      createuser --no-superuser --no-createdb --no-createrole "$1"
      createdb --owner="$1" "$1"
    }
    query() { psql "$(url "$1")" --no-psqlrc --quiet --tuples-only --no-align -v ON_ERROR_STOP=1 -c "$2"; }
    load() {
      createdb "$1"
      for file in "''${@:2}"; do
        psql "$(url "$1")" --no-psqlrc --quiet -v ON_ERROR_STOP=1 -f "$file" >/dev/null
      done
    }
    # The schema without schema_migrations, sorted, and without pg_dump's
    # random \restrict lines
    schema() {
      pg_dump "$(url "$1")" --schema-only --no-owner --exclude-table=schema_migrations \
        | grep -vE '^--|^$|^\\(un)?restrict ' | sort
    }
    revisions() {
      for file in "$IHP_MIGRATION_DIR"/*.sql; do
        basename "$file" | sed -n 's/^\([0-9][0-9]*\).*/\1/p'
      done | sort -n
    }

    passed=0
    pass() { echo "ok: $*"; passed=$((passed + 1)); }
    fail() { echo "FAIL: $*" >&2; exit 1; }

    load expected "$IHP_SCHEMA" "$APP_SCHEMA"
    schema expected > expected.sql

    # Staging, bootstrapped and migrated by its owner, who isn't a superuser
    ownedDatabase bosco_staging
    DATABASE_URL="$(url bosco_staging bosco_staging)" bootstrap-schema
    DATABASE_URL="$(url bosco_staging bosco_staging)" migrate
    schema bosco_staging > staging.sql
    diff expected.sql staging.sql || fail "the bootstrapped schema differs from Schema.sql"
    [ "$(query bosco_staging 'SELECT revision FROM schema_migrations ORDER BY revision')" = "$(revisions)" ] \
      || fail "not every migration is marked as applied"
    [ "$(query bosco_staging 'SELECT count(*) FROM products')" -gt 0 ] || fail "the fixtures were not loaded"
    pass "a new staging database gets the schema, the fixtures and every migration, as its owner"

    query bosco_staging "INSERT INTO customers (name, email, phone) VALUES ('Kept', 'kept@example.com', ''')"
    DATABASE_URL="$(url bosco_staging bosco_staging)" bootstrap-schema | grep -q "nothing to do" \
      || fail "bootstrap-schema touched a database with tables"
    [ "$(query bosco_staging 'SELECT count(*) FROM customers')" = 1 ] || fail "bootstrap-schema changed existing data"
    pass "bootstrapping again leaves the database alone"

    # Production before the first NixOS deploy: the snapshot schema restored by
    # the owner, no schema_migrations, and an order from before unit_price
    ownedDatabase bosco_fi
    for file in "$IHP_SCHEMA" ${./production-schema-1760540031.sql}; do
      psql "$(url bosco_fi bosco_fi)" --no-psqlrc --quiet -v ON_ERROR_STOP=1 -f "$file" >/dev/null
    done
    query bosco_fi "
      INSERT INTO producers (id, name, subject, description) VALUES ('00000000-0000-0000-0000-000000000001', 'Tila', ''', ''');
      INSERT INTO products (id, producer_id, name, description, package, price)
        VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Öljy', ''', '1 l', 1250);
      INSERT INTO customers (id, name, email, phone, reverse_name)
        VALUES ('00000000-0000-0000-0000-000000000003', 'Maija  Virtanen', 'maija@example.com', ''', ''');
      INSERT INTO orders (id, customer_id) VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000003');
      INSERT INTO ordered_products (order_id, product_id, quantity)
        VALUES ('00000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', 2);"

    createdb --template=bosco_fi --owner=bosco_fi production_without_minimum
    if DATABASE_URL="$(url production_without_minimum bosco_fi)" migrate 2>/dev/null; then
      fail "migrating production without minimumRevision should fail"
    fi
    pass "without minimumRevision the migrations applied before would run again, and fail"

    DATABASE_URL="$(url bosco_fi bosco_fi)" MINIMUM_REVISION=$minimumRevision migrate
    schema bosco_fi > production.sql
    diff expected.sql production.sql || fail "production's schema after the migrations differs from Schema.sql"
    [ "$(query bosco_fi 'SELECT revision FROM schema_migrations ORDER BY revision')" \
      = "$(revisions | while read -r revision; do [ "$revision" -gt "$minimumRevision" ] && echo "$revision"; done)" ] \
      || fail "production should have recorded exactly the migrations after $minimumRevision"
    pass "the first deploy applies only the migrations after $minimumRevision"

    [ "$(query bosco_fi 'SELECT unit_price FROM ordered_products')" = 1250 ] \
      || fail "the existing order line didn't get its product's price"
    [ "$(query bosco_fi 'SELECT reverse_name FROM customers')" = "virtanen maija" ] \
      || fail "the customer without a reverse name didn't get one"
    pass "existing orders and customers are filled in by the migrations"

    DATABASE_URL="$(url bosco_fi bosco_fi)" MINIMUM_REVISION=$minimumRevision migrate
    schema bosco_fi > production-again.sql
    diff production.sql production-again.sql || fail "migrating again changed the schema"
    pass "the next deploy finds nothing to migrate"

    echo "$passed tests passed"
    touch $out
  ''
