module Admin.View.Layout (defaultLayout, Html) where

import Admin.Routes
import Admin.Types
import Application.Helper.View
import Generated.Types
import IHP.Environment
import IHP.ViewPrelude
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

defaultLayout :: Html -> Html
defaultLayout inner = [hsx|
<!DOCTYPE html>
<html lang="fi">
<head>
    {metaTags}

    {stylesheets}
    {scripts}

    <title>{demoTitle (pageTitleOrDefault "Manage Bosco Falconeria")}</title>
</head>
<body>
    {demoStamp "This is a demo admin. Everyone using the demo sees your changes, and none of the orders are real."}
    <div class="container admin-container">
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
stylesheets = [hsx|
        <link rel="stylesheet" href={assetPath "/app.css"}/>
    |]

scripts :: Html
scripts = do
    when isDevelopment [hsx|
        {devScripts}
        <script src={assetPath "/vendor/timeago.js"}></script>
        <script src={assetPath "/vendor/morphdom-umd.min.js"}></script>
        <script src={assetPath "/vendor/turbolinks.js"}></script>
        <script src={assetPath "/vendor/turbolinksInstantClick.js"}></script>
        <script src={assetPath "/vendor/turbolinksMorphdom.js"}></script>
        <script src={assetPath "/helpers.js"}></script>
        <script src={assetPath "/ihp-auto-refresh.js"}></script>
        <script src={assetPath "/app.js"}></script>
    |]
    when isProduction [hsx|
        <script src={assetPath "/prod.js"}></script>
    |]

devScripts :: Html
devScripts = [hsx|
        <script id="livereload-script" src={assetPath "/livereload.js"} data-ws={liveReloadWebsocketUrl}></script>
    |]

metaTags :: Html
metaTags = [hsx|
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width"/>
    {demoHead}
    {autoRefreshMeta}
|]
