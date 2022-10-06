module Admin.Controller.Orders where

import Admin.Controller.Prelude
import Admin.View.Orders.Index
import Admin.View.Orders.Show

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        (ordersQ, pagination) <- query @Order |> paginate
        orders <- ordersQ |> fetch
        render IndexView { .. }

    action ShowOrderAction { orderId } = do
        order <- fetch orderId >>= fetchRelated #customerId
        render ShowView { .. }

    action MarkPaidOrderAction { orderId } = do
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #paidAt now
            |> updateRecord
        setSuccessMessage "Tilais maksettu"
        redirectTo ShowOrderAction { orderId }

    action CancelOrderAction { orderId } = do
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #cancelledAt now
            |> updateRecord
        setSuccessMessage "Tilais peruttu"
        redirectTo ShowOrderAction { orderId }
