# Development and checks, in the dev shell (`nix develop`, or direnv's
# `use flake`). `just` lists the recipes.
#
# The development state is in .dev/: the PostgreSQL database `bosco`, on a
# socket there, the session key and the logs. `just dev` starts it all.

set dotenv-load
set positional-arguments

root := justfile_directory()
dev := root / ".dev"

# For the programs run here; .env may set others, e.g. APP_LOCALE=en
export PGDATA := dev / "postgres"
export PGHOST := dev
export PGUSER := "postgres"
export PGDATABASE := "bosco"
export DATABASE_URL := "postgresql:///bosco?host=" + dev + "&user=postgres"
export IHP_SESSION_SECRET_FILE := dev / "session.aes"
export STATIC_DIR := root / "static"
# The worker only logs the emails it would send, unless .env says otherwise
export SEND_EMAILS := env("SEND_EMAILS", "0")
export RUST_LOG := env("RUST_LOG", "info")

# Lists the recipes
default:
    @just --list

# Rebuilt and restarted when their code changes, and the stylesheet when the
# markup does.
#
# The site at http://localhost:8003 and its email worker, rebuilt on changes
dev: db
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill 0' EXIT
    tailwindcss -i tailwind/app.css -o static/app.css --watch=always 2>"{{dev}}/tailwind.log" &
    cd rust-web
    # Built once first, so the two don't wait for each other's build
    cargo build --bin bosco-web --bin bosco-worker
    watchexec --restart --watch src --watch Cargo.toml --watch Cargo.lock \
        -- cargo run --quiet --bin bosco-worker &
    watchexec --restart --watch src --watch Cargo.toml --watch Cargo.lock \
        -- cargo run --quiet --bin bosco-web

# Made on first use with the schema, the Finnish catalog (db/Fixtures.sql)
# and the migrations, as a new staging instance on a server gets them.
#
# Starts the development database, making it on first use
db:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{dev}}"
    if [ ! -d "$PGDATA" ]; then
        initdb --username=postgres --auth=trust --encoding=UTF8 >/dev/null
        echo "unix_socket_directories = '{{dev}}'" >> "$PGDATA/postgresql.conf"
        echo "listen_addresses = ''" >> "$PGDATA/postgresql.conf"
    fi
    if ! pg_ctl status >/dev/null; then
        pg_ctl -l "{{dev}}/postgres.log" -w start >/dev/null
        echo "db: PostgreSQL started, log in .dev/postgres.log"
    fi
    if ! psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'bosco'" | grep -q 1; then
        createdb bosco
        IHP_SCHEMA=db/IHPSchema.sql APP_SCHEMA=db/Schema.sql APP_FIXTURES=db/Fixtures.sql \
            IHP_MIGRATION_DIR=db/Migration bash nix/bootstrap-schema.sh
    fi
    cd rust-web && cargo run --quiet --bin bosco-migrate

# Stops the development database
db-stop:
    -pg_ctl stop -m fast

# Removes the development database, to start again from the schema
db-reset: db-stop
    rm -rf "{{PGDATA}}"

# A psql shell on the development database
psql *args: db
    psql "$@"

# It refuses when the database has orders already.
#
# Adds orders, customers and a login for each role, printing the passwords
seed: db
    cd rust-web && cargo run --quiet --bin bosco-seed-dev

# Runs a program of rust-web/ on the development database, e.g. bosco-create-user
run program *args: db
    cd rust-web && cargo run --quiet --bin {{program}} -- "${@:2}"

# The Rust tests on a throwaway PostgreSQL; arguments go to cargo test
test *args:
    cd rust-web && ./test.sh "$@"

# Lints, tests, the NixOS module and the migrations: quick enough to run often
check: lint test
    #!/usr/bin/env bash
    set -euo pipefail
    system=$(nix eval --impure --raw --expr builtins.currentSystem)
    nix build --no-link -L ".#checks.$system.nixos-module" ".#checks.$system.deploy-migrations"

# Formatting and clippy's lints
lint:
    cd rust-web && cargo fmt --check
    cd rust-web && cargo clippy --all-targets --locked -- -D warnings

# Every check of the flake, the release build too; the pre-push hook runs it
check-all: check
    nix flake check -L
