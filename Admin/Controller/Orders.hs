module Admin.Controller.Orders where

import Admin.Controller.Prelude
import Admin.View.Orders.Index
import Admin.View.Orders.Show
import Web.Controller.Orders (countSum, groupOrderedProducts, sortProducers)

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        -- TODO filter to exclude handled orders
        (ordersQ, pagination) <- query @Order
            |> orderByDesc #orderedAt
            |> paginate
        orders <- ordersQ |> fetch >>= collectionFetchRelated #customerId
        render IndexView { .. }

    action ShowOrderAction { orderId } = do
        order <- fetch orderId >>= fetchRelated #customerId
        xs <- query @Producer
            |> orderBy #name
            |> fetch
        let producers = sortProducers xs
        xs <- query @OrderedProduct
            |> filterWhere (#orderId, order.id)
            |> fetch
            >>= collectionFetchRelated #productId
        let totalSum = countSum xs
        let orderedProductsByProducer = groupOrderedProducts xs
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
