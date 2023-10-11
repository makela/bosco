module Web.Types where

import Generated.Types
import IHP.ModelSupport
import IHP.Prelude

data WebApplication = WebApplication deriving (Eq, Show)

data OrdersController
    = OrdersAction
    | NewOrderAction
    | ShowOrderAction { orderId :: !(Id Order) }
    | CreateOrderAction
    | UpdateCancelOrderAction { orderId :: !(Id Order) }
    | NewEmailAction
    | CreateEmailAction
    deriving (Eq, Show, Data)
