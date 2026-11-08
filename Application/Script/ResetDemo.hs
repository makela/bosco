#!/usr/bin/env run-script
-- | Resets a public demo's data: the catalog from the fixtures, fake
-- payment details and a few seasons of made-up orders (Application/DemoData.hs).
-- Logins are kept. The NixOS module runs it every night on an instance
-- with demo = true; by hand:
--
--   APP_DEMO=1 SEND_EMAILS=0 run-script Application/Script/ResetDemo.hs
--
-- It refuses to run unless APP_DEMO is on, so it can't empty a real shop.
-- APP_FIXTURES is the fixtures file (Application/Fixtures.sql by default).
module Application.Script.ResetDemo where

import qualified Data.ByteString as ByteString
import qualified Data.Text.Encoding as TE

import IHP.EnvVar (envOrDefault)

import Application.DemoData (resetDemoData, seedFor)
import Application.Script.Prelude

run :: Script
run = do
    -- Read before any query: a bad setting would otherwise fail mid-query
    demo <- envOrDefault "APP_DEMO" False
    unless demo do
        error "APP_DEMO is off: this would empty a real shop's orders. Not resetting."
    fixturesPath :: Text <- envOrDefault "APP_FIXTURES" "Application/Fixtures.sql"
    -- As UTF-8 whatever the locale, which a systemd service may not have
    fixtures <- TE.decodeUtf8 <$> ByteString.readFile (cs fixturesPath)
    now <- getCurrentTime
    count <- resetDemoData fixtures (seedFor now) now
    putStrLn ("Reset the demo: " <> tshow count <> " orders")
