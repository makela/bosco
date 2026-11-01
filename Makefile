
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
TEST_CHECKS = tests integration-tests nixos-module deploy-migrations

# Runs Test/Main.hs and Test/Integration.hs (with its own PostgreSQL) plus the
# rest of the flake checks. New files under Test/ must be `git add`ed first.
# Nix reuses test results when nothing changed, so the summary comes from
# the log of the last real run. `nix log` on a check shows the full output.
.PHONY: check
check:
	@mkdir -p .devenv && printf %s "$$PWD" > .devenv/root
	@nix flake check $(DEVENV_ROOT); status=$$?; \
	system=$$(nix eval --impure --raw --expr builtins.currentSystem); \
	echo; echo "Test results:"; \
	for c in $(TEST_CHECKS); do \
		result=$$(nix log $(DEVENV_ROOT) ".#checks.$$system.$$c" 2>/dev/null \
			| sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
			| grep -E 'examples, |tests passed' | tr '\n' ' '); \
		echo "  $$c: $${result:-no result}"; \
	done; \
	exit $$status

# Fills a fresh dev database with orders, customers and logins to browse.
# Refuses to run if the database already has orders.
.PHONY: seed-dev
seed-dev:
	run-script Application/Script/SeedDevData.hs
