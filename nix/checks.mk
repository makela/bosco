# The flake checks: `make check` while working, `make check-all` before
# pushing. Included by the Makefile; kept out of the IHP app's source (see
# flake.nix), so that a change here doesn't rebuild the app.

# devenv needs to know the project directory; `nix develop` defaults it to /dev/null
DEVENV_ROOT = --override-input devenv-root "file+file://$$PWD/.devenv/root"
# The checks with tests, each with the name its build log lines start with
TEST_CHECKS = tests:bosco-tests integration-tests:bosco-integration-tests \
	nixos-module:nixos-module-tests deploy-migrations:deploy-migration-tests \
	rust-web-tests:bosco-rust-web-tests

# The checks `make check` leaves out, as they only build again what another
# check builds: the app with -O2 (optimized-prod-server, which the server
# runs; unoptimized-prod-server compiles the same code with -O0) and the Rust
# package (rust-web-tests builds it before testing it)
SLOW_CHECKS = optimized-prod-server rust-web

# The build's whole log, kept for a look at what failed
CHECK_LOG = .devenv/check.log

# Builds with $(1), its log in CHECK_LOG, showing only what is being built
# and what went wrong; then each test check's results, or that Nix reused it
# as nothing it reads changed since it last passed
define BUILD_CHECKS
mkdir -p .devenv && printf %s "$$PWD" > .devenv/root; \
$(1) -L $(DEVENV_ROOT) 2>&1 | tee $(CHECK_LOG) \
	| grep --line-buffered -E "^(building '|error)|^[^ ]+> .*(error|FAIL|panicked)"; \
status=$${PIPESTATUS[0]}; \
echo; if [ $$status = 0 ]; then echo "All checks passed$(2)."; else echo "Failed, see $(CHECK_LOG)"; fi; \
echo "Test results:"; \
for pair in $(TEST_CHECKS); do \
	check=$${pair%%:*}; name=$${pair#*:}; \
	result=$$(sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' $(CHECK_LOG) \
		| grep -E "^$$name> .*(examples, |tests passed|test result: ok\. [1-9])" \
		| sed "s/^$$name> *//" | tr '\n' ' '); \
	if [ -z "$$result" ]; then \
		if grep -q "^$$name> " $(CHECK_LOG); then result="no results in the log"; \
		else result="unchanged since it last passed"; fi; \
	fi; \
	echo "  $$check: $$result"; \
done; \
exit $$status
endef

# Runs Test/Main.hs and Test/Integration.hs (with its own PostgreSQL), the Rust
# site's tests (rust-web/) plus the rest of the flake checks, one of which
# compiles every Application/Script, and the NixOS module's; all but
# SLOW_CHECKS.
# New files under Test/ must be `git add`ed first.
.PHONY: check
check: SHELL := bash
check:
	@system=$$(nix eval --impure --raw --expr builtins.currentSystem); \
	checks=$$(nix eval --raw $(DEVENV_ROOT) ".#checks.$$system" \
		--apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)' 2>/dev/null); \
	targets=$$(for c in $$checks; do \
		case " $(SLOW_CHECKS) " in *" $$c "*) ;; *) echo ".#checks.$$system.$$c";; esac; \
	done); \
	$(call BUILD_CHECKS,nix build --no-link $$targets, (make check-all also builds $(SLOW_CHECKS)))

# Every flake check, SLOW_CHECKS too: what the pre-push hook runs
.PHONY: check-all
check-all: SHELL := bash
check-all:
	@$(call BUILD_CHECKS,nix flake check,)
