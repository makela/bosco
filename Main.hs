module Main where
import IHP.Prelude

import Admin.FrontController
import Admin.Types
import Config
import IHP.FrameworkConfig
import IHP.Job.Types
import IHP.RouterSupport
import qualified IHP.Server
import Web.FrontController
import Web.Types

instance FrontController RootApplication where
    controllers = [
            mountFrontController WebApplication
            , mountFrontController AdminApplication
        ]

main :: IO ()
main = IHP.Server.run config
