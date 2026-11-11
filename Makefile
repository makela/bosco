
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


# make check and make check-all; optional, as the IHP app's build has the
# Makefile without nix/
-include nix/checks.mk

# Fills a fresh dev database with orders, customers and logins to browse.
# Refuses to run if the database already has orders.
.PHONY: seed-dev
seed-dev:
	run-script Application/Script/SeedDevData.hs
