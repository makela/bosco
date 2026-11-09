module Application.Helper.View
    ( isDemo
    , demoTitle
    , demoHead
    , demoStamp
    , renderAddressLines
    , renderNameLines
    ) where

import IHP.FrameworkConfig (ConfigProvider)
import IHP.ViewPrelude

import Application.Customer (addressLines, nameLines)
import Application.Demo (isDemo)
import Generated.Types

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

-- | The customer's address, a paragraph per line
renderAddressLines :: Customer -> Html
renderAddressLines customer = forEach (addressLines customer) \line -> [hsx|<p>{line}</p>|]

-- | The name for the invoice or the company, if any, and the customer's name,
-- a paragraph each
renderNameLines :: Customer -> Html
renderNameLines customer = forEach (nameLines customer) \line -> [hsx|<p>{line}</p>|]
