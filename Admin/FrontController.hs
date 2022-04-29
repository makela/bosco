module Admin.FrontController where

import IHP.RouterPrelude
import Admin.Controller.Prelude
import Admin.View.Layout (defaultLayout)

-- Controller Imports
import Admin.Controller.WelcomeMessages
import Admin.Controller.Customers
import Admin.Controller.Producers
import Admin.Controller.Products
import Admin.Controller.Static

instance FrontController AdminApplication where
    controllers = 
        [ startPage WelcomeAction
        -- Generator Marker
        , parseRoute @WelcomeMessagesController
        , parseRoute @CustomersController
        , parseRoute @ProducersController
        , parseRoute @ProductsController
        , parseRoute @StaticController
        ]

instance InitControllerContext AdminApplication where
    initContext = do
        setLayout defaultLayout
        initAutoRefresh
