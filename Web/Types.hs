module Web.Types where

import IHP.Prelude
import IHP.ModelSupport
import Generated.Types

data WebApplication = WebApplication deriving (Eq, Show)

data OrdersController
    = OrdersAction
    | NewOrderAction
    | ShowOrderAction { orderId :: !(Id Order) }
    | CreateOrderAction
    | EditOrderAction { orderId :: !(Id Order) }
    | UpdateOrderAction { orderId :: !(Id Order) }
    | DeleteOrderAction { orderId :: !(Id Order) }
    deriving (Eq, Show, Data)
