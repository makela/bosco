module Web.FrontController where

import IHP.RouterPrelude
import Web.Controller.Prelude
import Web.View.Layout (defaultLayout)

-- Controller Imports
import Web.Controller.Orders

instance FrontController WebApplication where
    controllers =
        [ startPage OrdersAction
        -- Generator Marker
        , parseRoute @OrdersController
        ]

instance InitControllerContext WebApplication where
    initContext = do
        setLayout defaultLayout
