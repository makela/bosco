module Web.Controller.Orders where

import Web.Controller.Prelude
import Web.View.Orders.Index
import Web.View.Orders.New
import Web.View.Orders.Edit
import Web.View.Orders.Show

instance Controller OrdersController where
    action OrdersAction = do
        message <- query @WelcomeMessage |> fetchOneOrNothing
        now <- getCurrentTime
        let publishedAt = maybe now (get #publishedAt) message
            (y, _, _) = toGregorian $ utctDay publishedAt
            year = show y
        render IndexView { .. }

    action NewOrderAction = do
        let order = newRecord
        products <- query @Product |> fetch
        render NewView { .. }

    action ShowOrderAction { orderId } = do
        order <- fetch orderId
        render ShowView { .. }

    action EditOrderAction { orderId } = do
        order <- fetch orderId
        render EditView { .. }

    action UpdateOrderAction { orderId } = do
        order <- fetch orderId
        order
            |> buildOrder
            |> ifValid \case
                Left order -> render EditView { .. }
                Right order -> do
                    order <- order |> updateRecord
                    setSuccessMessage "Order updated"
                    redirectTo EditOrderAction { .. }

    action CreateOrderAction = do
        let order = newRecord @Order
        order
            |> buildOrder
            |> ifValid \case
                Left order -> do
                    products <- query @Product |> fetch
                    render NewView { .. }
                Right order -> do
                    order <- order |> createRecord
                    setSuccessMessage "Order created"
                    redirectTo OrdersAction

    action DeleteOrderAction { orderId } = do
        order <- fetch orderId
        deleteRecord order
        setSuccessMessage "Order deleted"
        redirectTo OrdersAction

buildOrder order = order
    |> fill @'["customerId"]
