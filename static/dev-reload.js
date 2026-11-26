// Development only (rust-web/src/dev_reload.rs): reloads the page when the
// site restarts or a static file changes.
(function () {
    var seen = null;
    setInterval(function () {
        fetch('/dev/reload', { cache: 'no-store' })
            .then(function (response) { return response.ok ? response.text() : null; })
            .then(function (version) {
                if (version === null) return;
                if (seen === null) seen = version;
                else if (version !== seen) location.reload();
            }, function () { /* restarting: ask again in a second */ });
    }, 1000);
})();
