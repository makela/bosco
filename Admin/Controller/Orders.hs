module Admin.Controller.Orders where

import qualified Data.Map as Map

import Admin.Controller.Prelude
import Admin.View.Orders.Index
import Admin.View.Orders.Show
import Admin.View.Orders.OrderedProducts
import Web.Controller.Orders (fetchShowOrderContext, groupOrderedProducts, sortProducers)

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        -- TODO exclude handled orders, separate Action/View?
        xs <- query @Order
            |> filterWhereSql (#cancelledAt, "IS NULL")
            |> fetch
            -- TODO should sort in database
            -- >>= pure . map (modify #customerId (orderBy #name))
            >>= collectionFetchRelated #customerId
        let orders = sortOn (\x -> toLower x.customerId.name) xs
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

    action OrderedProductsAction = do
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
