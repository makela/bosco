module Application.Helper.View
    ( isDemo
    , demoTitle
    , demoHead
    , demoStamp
    , renderAddressLines
    , renderNameLines
    , honeypotField
    ) where

import IHP.FrameworkConfig (ConfigProvider)
import IHP.ViewPrelude

import Application.Customer (addressLines, nameLines)
import Application.Localization
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

-- | A field for bots only, in every public form. People don't see it or
-- reach it with the keyboard, screen readers skip it, and browsers don't
-- fill it in, but a bot fills in every field, so a form with it filled in
-- is ignored, see 'unlessSpam' in "Application.Helper.Controller". Hidden
-- off the page, not with type="hidden", which bots leave alone. The name is
-- also in 'honeypotName'.
honeypotField :: Html
honeypotField = [hsx|
    <div class="honeypot" aria-hidden="true">
        <label for="contact_me_by_fax_only">{l10nText LLeaveEmpty}</label>
        <input type="text" name="contact_me_by_fax_only" id="contact_me_by_fax_only" value="" tabindex="-1" autocomplete="off"/>
    </div>
|]
