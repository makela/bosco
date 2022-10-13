document.addEventListener('DOMContentLoaded', function() {
    var body = document.querySelector('body')
    body.addEventListener('click', function(e) {
        if (e.target.tagName === "A") {
            var href = e.target.getAttribute('href')
            if (href.startsWith('http')) {
                window.open(href, '_blank')
                e.preventDefault()
                return false
            }
        }
    })
})
