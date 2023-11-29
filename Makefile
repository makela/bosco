
CSS_FILES += static/app.css

JS_FILES += ${IHP}/static/helpers.js
JS_FILES += ${IHP}/static/vendor/morphdom-umd.min.js
JS_FILES += ${IHP}/static/vendor/turbolinks.js
JS_FILES += ${IHP}/static/vendor/turbolinksInstantClick.js
JS_FILES += ${IHP}/static/vendor/turbolinksMorphdom.js
JS_FILES += static/app.js

include ${IHP}/Makefile.dist

tailwind-dev:
	tailwindcss -c tailwind/tailwind.config.js -i ./tailwind/app.css -o static/app.css --watch

static/app.css:
	tailwindcss -c tailwind/tailwind.config.js -i ./tailwind/app.css -o static/app.css --minify

