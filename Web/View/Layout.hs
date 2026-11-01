module Web.View.Layout (defaultLayout, Html) where

import IHP.ViewPrelude
import IHP.Environment
import qualified Text.Blaze.Html5            as H
import qualified Text.Blaze.Html5.Attributes as A
import Generated.Types
import Web.Types
import Web.Routes
import Application.Helper.View

defaultLayout :: Html -> Html
defaultLayout inner = [hsx|
<!DOCTYPE html>
<html lang="fi">
<head>
    {metaTags}

    {stylesheets}
    {scripts}

    <title>{pageTitleOrDefault "Bosco Falconeria Öljytilaus"}</title>
</head>
<body>
    <div class="container">
        <a href="http://www.boscofalconeria.it/">
            <img src="/img/logo.jpg" alt="Bosco Falconeria logo" />
        </a>
        {renderFlashMessages}
        {inner}
    </div>
</body>
</html>
|]

-- The 'assetPath' function used below appends a `?v=SOME_VERSION` to the static assets in production
-- This is useful to avoid users having old CSS and JS files in their browser cache once a new version is deployed
-- See https://ihp.digitallyinduced.com/Guide/assets.html for more details

stylesheets :: Html
stylesheets = do
    when isDevelopment [hsx|
        <link rel="stylesheet" href={assetPath "/app.css"}/>
    |]
    when isProduction [hsx|
        <link rel="stylesheet" href={assetPath "/prod.css"}/>
    |]

scripts :: Html
scripts = do
    when isDevelopment [hsx|
        <script id="livereload-script" src={assetPath "/livereload.js"} data-ws={liveReloadWebsocketUrl}></script>
        <script src={assetPath "/vendor/morphdom-umd.min.js"}></script>
        <script src={assetPath "/vendor/turbolinks.js"}></script>
        <script src={assetPath "/vendor/turbolinksInstantClick.js"}></script>
        <script src={assetPath "/vendor/turbolinksMorphdom.js"}></script>
        <script src={assetPath "/helpers.js"}></script>
        <script src={assetPath "/app.js"}></script>
    |]
    when isProduction [hsx|
        <script src={assetPath "/prod.js"}></script>
    |]

metaTags :: Html
metaTags = [hsx|
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width"/>
    <meta property="og:title" content="Bosco Falconeria Öljytilaus"/>
    <meta property="og:type" content="website"/>
    <meta property="og:url" content="TODO"/>
    <meta property="og:description" content="Bosco Falconerian öljytilauslomake"/>
    {autoRefreshMeta}
|]
