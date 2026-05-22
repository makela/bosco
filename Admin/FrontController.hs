module Admin.FrontController where

import Admin.Controller.Prelude
import Admin.View.Layout (defaultLayout)
import IHP.LoginSupport.Middleware
import IHP.RouterPrelude

-- Controller Imports
import Admin.Controller.Customers
import Admin.Controller.Orders
import Admin.Controller.Passwords
import Admin.Controller.PaymentInstructions
import Admin.Controller.Producers
import Admin.Controller.Products
import Admin.Controller.Sessions
import Admin.Controller.Static
import Admin.Controller.WelcomeMessages

instance FrontController AdminApplication where
    controllers =
        [ startPage WelcomeAction
        , parseRoute @SessionsController
        -- Generator Marker
        , parseRoute @PaymentInstructionsController
        , parseRoute @OrdersController
        , parseRoute @WelcomeMessagesController
        , parseRoute @CustomersController
        , parseRoute @ProducersController
        , parseRoute @ProductsController
        , parseRoute @StaticController
        , parseRoute @PasswordsController
        ]

instance InitControllerContext AdminApplication where
    initContext = do
        setLayout defaultLayout
        initAuthentication @User
