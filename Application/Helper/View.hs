module Application.Helper.View
    ( isDemo
    , demoTitle
    , demoHead
    , demoStamp
    ) where

import IHP.FrameworkConfig (ConfigProvider)
import IHP.ViewPrelude

import Application.Demo (isDemo)

-- | Marks the page title of a demo, so tabs and bookmarks say it too
demoTitle :: (?context :: context, ConfigProvider context) => Text -> Text
demoTitle title
    | isDemo = "[Demo] " <> title
    | otherwise = title

-- | Keeps search engines from listing a demo next to the real shop
demoHead :: Html
demoHead = when isDemo [hsx|<meta name="robots" content="noindex, nofollow"/>|]

-- | A banner at the top of every page of a demo with the given text, and a
-- "DEMO" ribbon in the corner that stays in view while scrolling
demoStamp :: Text -> Html
demoStamp text = when isDemo [hsx|
    <div class="demo-banner" role="note">{text}</div>
    <div class="demo-ribbon" aria-hidden="true">DEMO</div>
|]
