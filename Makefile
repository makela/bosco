
CSS_FILES += static/app.css

JS_FILES += ${IHP}/static/helpers.js
JS_FILES += ${IHP}/static/vendor/morphdom-umd.min.js
JS_FILES += ${IHP}/static/vendor/turbolinks.js
JS_FILES += ${IHP}/static/vendor/turbolinksInstantClick.js
JS_FILES += ${IHP}/static/vendor/turbolinksMorphdom.js
JS_FILES += static/app.js

include ${IHP}/Makefile.dist

static/app.css:
	tailwindcss -i tailwind/app.css -o static/app.css --minify


# devenv needs to know the project directory; `nix develop` defaults it to /dev/null
DEVENV_ROOT = --override-input devenv-root "file+file://$$PWD/.devenv/root"
TEST_CHECKS = tests integration-tests nixos-module deploy-migrations rust-web-tests

# The checks `make check` leaves out, as they only build again what another
# check builds: the app with -O2 (optimized-prod-server, which the server
# runs; unoptimized-prod-server compiles the same code with -O0) and the Rust
# package (rust-web-tests builds it before testing it)
SLOW_CHECKS = optimized-prod-server rust-web

# The tests' results. Nix reuses a test's result when nothing it reads
# changed, so this comes from the log of its last real run. `nix log` on a
# check shows the full output.
define SUMMARY
system=$$(nix eval --impure --raw --expr builtins.currentSystem); \
echo; echo "Test results:"; \
for c in $(TEST_CHECKS); do \
	result=$$(nix log $(DEVENV_ROOT) ".#checks.$$system.$$c" 2>/dev/null \
		| sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
		| grep -E 'examples, |tests passed|test result: ok\. [1-9]' | tr '\n' ' '); \
	echo "  $$c: $${result:-no result}"; \
done
endef

# Runs Test/Main.hs and Test/Integration.hs (with its own PostgreSQL), the Rust
# site's tests (rust-web/) plus the rest of the flake checks, one of which
# compiles every Application/Script, and the NixOS module's; all but
# SLOW_CHECKS.
# New files under Test/ must be `git add`ed first.
.PHONY: check
check:
	@mkdir -p .devenv && printf %s "$$PWD" > .devenv/root
	@system=$$(nix eval --impure --raw --expr builtins.currentSystem); \
	checks=$$(nix eval --raw $(DEVENV_ROOT) ".#checks.$$system" \
		--apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)' 2>/dev/null); \
	targets=$$(for c in $$checks; do \
		case " $(SLOW_CHECKS) " in *" $$c "*) ;; *) echo ".#checks.$$system.$$c";; esac; \
	done); \
	nix build --no-link $(DEVENV_ROOT) $$targets && echo "all checks passed (but $(SLOW_CHECKS))"; \
	status=$$?; \
	$(SUMMARY); \
	exit $$status

# Every flake check, SLOW_CHECKS too: what the pre-push hook runs
.PHONY: check-all
check-all:
	@mkdir -p .devenv && printf %s "$$PWD" > .devenv/root
	@nix flake check $(DEVENV_ROOT); status=$$?; \
	$(SUMMARY); \
	exit $$status

# Fills a fresh dev database with orders, customers and logins to browse.
# Refuses to run if the database already has orders.
.PHONY: seed-dev
seed-dev:
	run-script Application/Script/SeedDevData.hs
