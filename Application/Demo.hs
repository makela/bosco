-- | A public demo (APP_DEMO, see nix/module.nix)
module Application.Demo
    ( isDemo
    ) where

import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider)

import Application.Settings (DemoMode (..))

-- | Whether this instance is a public demo
isDemo :: (?context :: context, ConfigProvider context) => Bool
isDemo = let DemoMode demo = getAppConfig @DemoMode in demo
