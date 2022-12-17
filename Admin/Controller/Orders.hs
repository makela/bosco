module Admin.Controller.Orders where

import qualified Data.Map as Map

import Text.Regex.TDFA

import Admin.Controller.Prelude
import Admin.View.Orders.Index
import Admin.View.Orders.Show
import Admin.View.Orders.OrderedProducts
import Web.Controller.Orders (fetchShowOrderContext, groupOrderedProducts, sortProducers)

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        let q = paramOrDefault @Text "" "q"
        let excludePaid = paramOrDefault @Bool False "excludePaid"
        let excludeDelivered = paramOrDefault @Bool False "excludeDelivered"
        -- TODO exclude handled orders, separate Action/View?
        xs <- query @Order
            |> filterWhereSql (#cancelledAt, "IS NULL")
            |> fetch
            -- TODO should sort in database
            -- >>= pure . map (modify #customerId (orderBy #name))
            >>= collectionFetchRelated #customerId
        let orders = xs
                -- TODO should filter in database
                |> filter (\x -> if q == "" then True else toLower x.customerId.name =~ toLower q)
                |> filter (\x -> if excludePaid then not (isJust x.paidAt) else True)
                |> filter (\x -> if excludeDelivered then not (isJust x.deliveredAt) else True)
                |> sortOn (\x -> toLower x.customerId.name)
        render IndexView { .. }

    action ShowOrderAction { orderId } = do
        user <- fetch currentUserId
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
        render ShowView { .. }

    action UpdateMarkPaidOrderAction { orderId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #paidAt now
            |> updateRecord
        setSuccessMessage "Order paid"
        redirectTo ShowOrderAction { orderId }

    action UpdateCancelOrderAction { orderId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #cancelledAt now
            |> updateRecord
        setSuccessMessage "Order cancelled"
        redirectTo ShowOrderAction { orderId }

    action UpdateDeliverOrderAction { orderId } = do
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #deliveredAt now
            |> updateRecord
        setSuccessMessage "Order delivered"
        redirectTo ShowOrderAction { orderId }

    action OrderedProductsAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        orders <- query @Order
            |> filterWhereSql (#cancelledAt, "IS NULL")
            |> fetch
        let orderIds = map (.id) orders
        xs <- query @OrderedProduct
            |> filterWhereIn (#orderId, orderIds)
            |> fetch
            >>= collectionFetchRelated #productId
        let orderedProductsByProducer = groupOrderedProducts $ reverse $ sortOn (.productId.name) $ mergeByProductId xs
        xs <- query @Producer
            |> filterWhereIn (#id, Map.keys orderedProductsByProducer)
            |> orderBy #name
            |> fetch
        let producers = sortProducers xs
        render OrderedProductsView { .. }

mergeByProductId orders = go [] orders
    where go acc [] = acc
          go acc (x:xs) =
              let q = x.quantity + (sum $ map (.quantity) (filter (\y -> x.productId == y.productId) xs))
              in go (x { quantity = q } : acc) (filter (\y -> x.productId /= y.productId) xs)
