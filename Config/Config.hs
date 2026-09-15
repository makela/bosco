module Config where

import IHP.Prelude
import IHP.Environment
import IHP.FrameworkConfig
import IHP.LoginSupport.Middleware
import IHP.View.CSSFramework

import Admin.Controller.Prelude

config :: ConfigBuilder
config = do
    option $ AuthMiddleware (authMiddleware @User)
    option tailwind
