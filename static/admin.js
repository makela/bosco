// The admin's script, in place of the IHP app's prod.js: only what the Rust
// admin's pages use of it. Forms and links work without it.
document.addEventListener('DOMContentLoaded', function () {
    // A js-delete link asks first, unless it's js-delete-no-confirm, then
    // sends a POST with _method=DELETE to its address, which the site takes
    // as a DELETE, as IHP's links did.
    document.querySelectorAll('a.js-delete').forEach(function (link) {
        link.addEventListener('click', function (event) {
            event.preventDefault();
            var question = link.dataset.confirm || 'Are you sure you want to delete this?';
            if (!link.classList.contains('js-delete-no-confirm') && !window.confirm(question)) {
                return;
            }
            var form = document.createElement('form');
            form.method = 'POST';
            form.action = link.href;
            var method = document.createElement('input');
            method.type = 'hidden';
            method.name = '_method';
            method.value = 'DELETE';
            form.appendChild(method);
            document.body.appendChild(form);
            form.submit();
        });
    });

    // A time the server wrote in UTC, in the browser's own time zone and
    // date format, as IHP's dateTime did.
    document.querySelectorAll('time.date-time').forEach(function (time) {
        var date = new Date(time.dateTime);
        if (isNaN(date)) return;
        time.textContent = date.toLocaleDateString() + ', '
            + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    });
});
