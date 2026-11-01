module Config where

import Control.Exception (evaluate)

import IHP.Environment
import IHP.FrameworkConfig
import IHP.LoginSupport.Middleware
import IHP.Prelude
import IHP.View.CSSFramework

import Admin.Controller.Prelude
import Application.Localization (defaultLocale)

config :: ConfigBuilder
config = do
    option $ AuthMiddleware (authMiddleware @User)
    option tailwind

    -- The instance's language (APP_LOCALE), see Application.Localization.
    -- Read here too, so a wrong value stops the server at startup.
    liftIO (evaluate defaultLocale) >> pure ()
