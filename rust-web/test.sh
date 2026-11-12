#!/usr/bin/env bash
# Runs the tests against a throwaway PostgreSQL in a temporary directory,
# which is removed afterwards: `just test` in the dev shell. Extra arguments
# go to cargo test, e.g. `just test refuses`
set -euo pipefail
dir=$(mktemp -d)
export PGDATA="$dir/data" PGHOST="$dir/socket"
mkdir -p "$PGHOST"
initdb -D "$PGDATA" --username=postgres --auth=trust --encoding=UTF8 >/dev/null
echo "unix_socket_directories = '$PGHOST'" >> "$PGDATA/postgresql.conf"
echo "listen_addresses = ''" >> "$PGDATA/postgresql.conf"
pg_ctl -D "$PGDATA" -l "$dir/postgres.log" -w start >/dev/null
trap 'pg_ctl -D "$PGDATA" stop -m fast >/dev/null; rm -rf "$dir"' EXIT
# sqlx::test makes a database of its own for each test on this server
export DATABASE_URL="postgresql:///postgres?host=$PGHOST&user=postgres"
cargo test "$@"
