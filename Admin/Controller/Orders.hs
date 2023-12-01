module Admin.Controller.Orders where

import qualified Data.Map as Map
import qualified Data.Text.Encoding as E

import Text.Regex.TDFA

import Admin.Controller.Prelude
import Admin.View.Orders.Index
import Admin.View.Orders.OrderedProducts
import Admin.View.Orders.Show
import Web.Controller.Orders (createOrder, fetchShowOrderContext,
                              groupOrderedProducts, groupProducts,
                              sortProducers)
import Web.View.Orders.New

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        (yearNow, years) <- queryYears
        let year = paramOrDefault @Integer yearNow "year"
        let q = paramOrDefault @Text "" "q"
        let ordering = paramOrDefault @OrderBy OrderByName "ordering"
        let orderDir = paramOrDefault @OrderDir OrderByAsc "orderDir"
        let excludePaid = paramOrDefault @Bool False "excludePaid"
        let excludeDelivered = paramOrDefault @Bool False "excludeDelivered"
        let dateAfter = ">= '" <> tshow year <> "-01-01 00:00:00'"
        let dateBefore = "< '" <> tshow (year + 1) <> "-01-01 00:00:00'"
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
                |> filter (\x -> if q == "" then True else toLower x.customerId.name =~ toLower q)
                |> filter (\x -> if excludePaid then not (isJust x.paidAt) else True)
                |> filter (\x -> if excludeDelivered then not (isJust x.deliveredAt) else True)
        let orders'' = case ordering of
                        OrderByName      -> orders' |> sortOn (\x -> toLower x.customerId.name)
                        OrderByOrderedAt -> orders' |> sortOn (\x -> x.orderedAt)
        let orders = case orderDir of
                        OrderByAsc  -> orders''
                        OrderByDesc -> reverse orders''
        render IndexView { .. }

    action NewOrderAction = do
        xs <- fetchProducers
        let producers = sortProducers xs
        products <- fetchProducts
        let orders = mempty
        let productsByProducers = groupProducts products
        let customer = newRecord @Customer
        let actionUrl = pathTo CreateOrderAction
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
        redirectTo ShowOrderAction { orderId }

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

    action OrderedProductsAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (yearNow, years) <- queryYears
        let year = paramOrDefault @Integer yearNow "year"
        let dateAfter = ">= '" <> tshow year <> "-01-01 00:00:00'"
        let dateBefore = "< '" <> tshow (year + 1) <> "-01-01 00:00:00'"
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

mergeByProductId orders = go [] orders
    where go acc [] = acc
          go acc (x:xs) =
              let q = x.quantity + (sum $ map (.quantity) (filter (\y -> x.productId == y.productId) xs))
              in go (x { quantity = q } : acc) (filter (\y -> x.productId /= y.productId) xs)


queryYears :: (?context::ControllerContext, ?modelContext::ModelContext) => IO (Integer, [Integer])
queryYears = do
    now <- getCurrentTime
    let (yearNow, _, _) = toGregorian $ utctDay now
    firstOrder <- query @Order
        |> orderByAsc #orderedAt
        |> fetchOneOrNothing
    let maybeFirstYear = fmap ((\(y, _, _) -> y) . toGregorian . utctDay . (\x -> x.orderedAt)) firstOrder
    let firstYear = fromMaybe yearNow maybeFirstYear
    let years = [firstYear .. yearNow]
    pure (yearNow, years)

fetchProducers :: (?modelContext :: ModelContext) =>IO [Producer]
fetchProducers = do
    query @Producer
        |> orderByDesc #name
        |> fetch

fetchProducts :: (?modelContext :: ModelContext) =>IO [Product]
fetchProducts = do
    query @Product
        |> orderByDesc #ordering
        |> orderByDesc #name
        |> fetch
