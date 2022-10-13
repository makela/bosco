module Admin.Controller.Orders where

import Admin.Controller.Prelude
import Admin.View.Orders.Index
import Admin.View.Orders.Show
import Web.Controller.Orders (fetchShowOrderContext)

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        -- TODO exclude handled orders, separate Action/View?
        (ordersQ, pagination) <- query @Order
            |> orderByDesc #orderedAt
            |> paginate
        orders <- ordersQ |> fetch >>= collectionFetchRelated #customerId
        render IndexView { .. }

    action ShowOrderAction { orderId } = do
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
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
