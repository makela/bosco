module Application.NotFound (localizedNotFound, notFoundPage) where

import IHP.Prelude
import Network.HTTP.Types (hAccept, hContentType, status404, statusCode)
import Network.Wai (Middleware, Request, pathInfo, requestHeaders, responseHeaders, responseLBS, responseStatus)
import qualified Data.ByteString as ByteString
import IHP.HSX.Markup (Markup, renderMarkup)
import IHP.HSX.MarkupQQ (hsx)
import IHP.Environment (Environment (..))
import IHP.ModelSupport (RecordNotFoundException)

import Application.Localization

-- | Every page not found in the instance's language. IHP's own not found
-- page, or static/404.html, is the same file for every instance, so it would
-- be in one language for all of them. This replaces any HTML 404 the app
-- sends: an unknown address, a missing record, 'renderNotFound'. The admin
-- is in English on every instance, so are its pages not found.
--
-- In production IHP answers a missing record (e.g. 'fetch' of an order that
-- isn't there) with its not found page outside this middleware, so that is
-- caught here too. In development IHP's error page about it stays.
--
-- Files under /static/ are served before the middleware, so a missing one
-- still gets IHP's page; people don't visit those addresses.
localizedNotFound :: Environment -> Middleware
localizedNotFound environment app request respond = catchMissingRecord $ app request \response ->
    if statusCode (responseStatus response) == 404 && isHtml response
        then notFound
        else respond response
  where
    notFound = respond $ responseLBS status404
        [(hContentType, "text/html; charset=utf-8")]
        (renderMarkup (notFoundPage (pageLocale request)))
    isHtml response = maybe False ("text/html" `ByteString.isPrefixOf`) (lookup hContentType (responseHeaders response))
    -- Like IHP, which answers one asking for JSON in JSON
    wantsJson = maybe False ("application/json" `ByteString.isPrefixOf`) (lookup hAccept (requestHeaders request))
    catchMissingRecord action
        | environment == Production && not wantsJson =
            action `catch` \(_ :: RecordNotFoundException) -> notFound
        | otherwise = action

pageLocale :: Request -> Locale
pageLocale request = case pathInfo request of
    "admin" : _ -> EN
    _ -> defaultLocale

-- | Standalone, without the site's stylesheet: the middleware runs outside
-- IHP's, so it has no 'assetPath' for prod.css. The style is like .container
-- and p in tailwind/app.css. HSX copies a <style> as it is, without {}.
notFoundPage :: Locale -> Markup
notFoundPage locale = [hsx|
<!DOCTYPE html>
<html lang={localeCode locale}>
<head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width"/>
    <meta name="robots" content="noindex"/>
    <title>{l10nText' LPageNotFoundTitle locale} – {l10nText' LSiteTitle locale}</title>
    <style>
        body { margin: 0; font-family: ui-sans-serif, system-ui, sans-serif; line-height: 1.5 }
        main { max-width: 56rem; margin: 0 auto; padding: 0.5rem 0.5rem 2rem }
        img { display: block; max-width: 100%; height: auto }
        h1 { margin: 1rem; font-size: 1.5rem }
        p { margin: 1rem }
    </style>
</head>
<body>
    <main>
        <a href="/"><img src="/img/logo.jpg" alt="Bosco Falconeria logo"/></a>
        <h1>{l10nText' LPageNotFoundTitle locale}</h1>
        <p>{l10nText' LPageNotFound locale}</p>
    </main>
</body>
</html>
|]
