module Admin.Controller.Orders where

import qualified Data.Map as Map
import qualified Data.Text.Encoding as E

import Text.Regex.TDFA

import Admin.Controller.Prelude
import Admin.View.Orders.Index
import Admin.View.Orders.OrderedProducts
import Admin.View.Orders.Show
import Web.Controller.Orders (countSum, createOrder, fetchShowOrderContext,
                              groupOrderedProducts, groupProducts,
                              sortProducers)
import Web.View.Orders.New

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        (yearNow, years) <- queryYears
        let year = paramOrDefault @Integer yearNow "year"
            q = paramOrDefault @Text "" "q"
            ordering = paramOrDefault @OrderBy OrderByName "ordering"
            orderDir = paramOrDefault @OrderDir OrderByAsc "orderDir"
            excludeInvoiced = paramOrDefault @Bool False "excludeInvoiced"
            excludePaid = paramOrDefault @Bool False "excludePaid"
            excludeDelivered = paramOrDefault @Bool False "excludeDelivered"
            dateAfter = ">= '" <> tshow year <> "-01-01 00:00:00'"
            dateBefore = "< '" <> tshow (year + 1) <> "-01-01 00:00:00'"
        -- TODO exclude handled orders, separate Action/View?
        xs <- query @Order
            |> filterWhereSql (#cancelledAt, "IS NULL")
            |> filterWhereSql (#orderedAt, E.encodeUtf8 dateAfter)
            |> filterWhereSql (#orderedAt, E.encodeUtf8 dateBefore)
            |> fetch
            -- TODO should sort in database
            -- >>= pure . map (modify #customerId (orderBy #name))
            >>= collectionFetchRelated #customerId
        let orders' = xs
                -- TODO should filter in database
                |> filter (\x -> q == "" || toLower x.customerId.name =~ toLower q)
                |> filter (\x -> not excludeInvoiced || isNothing x.invoicedAt)
                |> filter (\x -> not excludePaid || isNothing x.paidAt)
                |> filter (\x -> not excludeDelivered || isNothing x.deliveredAt)
        prices <- mapM priceForOrder orders'
        let priceMap = Map.fromList prices
        let orders'' = case ordering of
                        OrderByName      -> orders' |> sortOn (toLower . (.customerId.name))
                        OrderByOrderedAt -> orders' |> sortOn (.orderedAt)
                        OrderByPrice -> orders' |> sortOn (\x -> Map.lookup x.id priceMap)
        let orders = case orderDir of
                        OrderByAsc  -> orders''
                        OrderByDesc -> reverse orders''
        render IndexView { .. }

    action NewOrderAction = do
        xs <- fetchProducers
        products <- fetchProducts
        let producers = sortProducers xs
            orders = mempty
            productsByProducers = groupProducts products
            customer = newRecord @Customer
            actionUrl = pathTo CreateOrderAction
        render NewView { .. }

    action ShowOrderAction { orderId } = do
        user <- fetch currentUserId
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
        render ShowView { .. }

    action CreateOrderAction = do
        producers <- fetchProducers
        products <- fetchProducts
        let actionUrl = pathTo CreateOrderAction
        createOrder actionUrl producers products $ \order -> do
            setSuccessMessage "Order created"
            redirectTo ShowOrderAction { orderId = order.id }

    action UpdateMarkPaidOrderAction { orderId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #paidAt now
            |> updateRecord
        setSuccessMessage "Order paid"
        redirectTo OrdersAction

    action DeleteCancelOrderAction { orderId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #cancelledAt now
            |> updateRecord
        setSuccessMessage "Order cancelled"
        redirectTo OrdersAction

    action UpdateDeliverOrderAction { orderId } = do
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #deliveredAt now
            |> updateRecord
        setSuccessMessage "Order delivered"
        redirectTo ShowOrderAction { orderId }

    action UpdateInvoiceOrderAction { orderId } = do
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #invoicedAt now
            |> updateRecord
        setSuccessMessage "Order invoiced"
        redirectTo ShowOrderAction { orderId }

    action OrderedProductsAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (yearNow, years) <- queryYears
        let year = paramOrDefault @Integer yearNow "year"
            dateAfter = ">= '" <> tshow year <> "-01-01 00:00:00'"
            dateBefore = "< '" <> tshow (year + 1) <> "-01-01 00:00:00'"
        orders <- query @Order
            |> filterWhereSql (#cancelledAt, "IS NULL")
            |> filterWhereSql (#orderedAt, E.encodeUtf8 dateAfter)
            |> filterWhereSql (#orderedAt, E.encodeUtf8 dateBefore)
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

mergeByProductId = go []
    where go acc [] = acc
          go acc (x:xs) =
              let q = x.quantity + sum (map (.quantity) (filter (\y -> x.productId == y.productId) xs))
              in go (x { quantity = q } : acc) (filter (\y -> x.productId /= y.productId) xs)


queryYears :: (?context::ControllerContext, ?modelContext::ModelContext) => IO (Integer, [Integer])
queryYears = do
    now <- getCurrentTime
    firstOrder <- query @Order
        |> orderByAsc #orderedAt
        |> limit 1
        |> fetchOneOrNothing
    lastOrder <- query @Order
        |> orderByDesc #orderedAt
        |> limit 1
        |> fetchOneOrNothing
    let (yearNow, _, _) = toGregorian $ utctDay now
        maybeFirstYear = maybeYear firstOrder
        maybeLastYear = maybeYear lastOrder
        firstYear = fromMaybe yearNow maybeFirstYear
        lastYear = fromMaybe yearNow maybeLastYear
        years = [firstYear .. lastYear]
    pure (lastYear, years)
    where maybeYear = fmap ((\(y, _, _) -> y) . toGregorian . utctDay . (.orderedAt))

fetchProducers :: (?modelContext :: ModelContext) => IO [Producer]
fetchProducers = do
    query @Producer
        |> orderByDesc #name
        |> fetch

fetchProducts :: (?modelContext :: ModelContext) => IO [Product]
fetchProducts = do
    query @Product
        |> orderByDesc #ordering
        |> orderByDesc #name
        |> fetch

priceForOrder :: (?modelContext :: ModelContext) => Include "customerId" Order -> IO (Id Order, Int)
priceForOrder order = do
    xs <- query @OrderedProduct
        |> filterWhere (#orderId, order.id)
        |> fetch
        >>= collectionFetchRelated #productId
    let totalSum = countSum xs
    return (order.id, totalSum)
