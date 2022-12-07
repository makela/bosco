module Web.Types where

import IHP.Prelude
import IHP.ModelSupport
import Generated.Types

data WebApplication = WebApplication deriving (Eq, Show)

data OrdersController
    = OrdersAction
    -- | NewOrderAction
    | ShowOrderAction { orderId :: !(Id Order) }
    | CreateOrderAction
    | UpdateCancelOrderAction { orderId :: !(Id Order) }
    | NewEmailAction
    | CreateEmailAction
    deriving (Eq, Show, Data)
