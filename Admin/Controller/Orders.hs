module Admin.Controller.Orders where

import qualified Data.Map as Map

import Data.Ord

import Admin.Controller.Prelude hiding (createOrder)
import Application.Customer (fullName)
import Application.Settings (EmailsEnabled (..))
import Admin.View.Orders.Index
import Admin.View.Orders.OrderedProducts
import Admin.View.Orders.Show
import Application.Sorting (sortProducers)
import Web.Controller.Orders (createOrder, fetchShowOrderContext,
                              groupProducts)
import Web.View.Orders.New

instance Controller OrdersController where
    beforeAction = ensureIsUser

    action OrdersAction = do
        user <- requirePermission SeeOrders
        let canManageOrders = can user ManageOrders
            canCreateOrders = can user CreateOrders
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
            |> filterWhereSql (#orderedAt, dateAfter)
            |> filterWhereSql (#orderedAt, dateBefore)
            |> fetch
            -- TODO should sort in database
            -- >>= pure . map (modify #customerId (orderBy #name))
            >>= collectionFetchRelated #customerId
        let orders' = xs
                -- TODO should filter in database
                |> filter (\x -> any (matchesSearch q) [fullName x.customerId, x.customerId.reverseName, x.customerId.billingName])
                |> filter (\x -> not excludeInvoiced || isNothing x.invoicedAt)
                |> filter (\x -> not excludePaid || isNothing x.paidAt)
                |> filter (\x -> not excludeDelivered || isNothing x.deliveredAt)
        -- All order lines in one query, summed per order
        orderLines <- query @OrderedProduct
            |> filterWhereIn (#orderId, map (.id) orders')
            |> fetch
        let priceMap = Map.fromListWith (+) $
                map (\x -> (x.id, 0)) orders'
                <> map (\x -> (x.orderId, x.unitPrice * x.quantity)) orderLines
        let orders'' = case ordering of
                        OrderByName      -> orders' |> sortOn (.customerId.reverseName)
                        OrderByOrderedAt -> orders' |> sortOn (.orderedAt)
                        OrderByPrice -> orders' |> sortOn (\x -> Map.lookup x.id priceMap)
        let orders = case orderDir of
                        OrderByAsc  -> orders''
                        OrderByDesc -> reverse orders''
        render IndexView { .. }

    action NewOrderAction = do
        _ <- requirePermission CreateOrders
        producers <- fetchProducers
        products <- fetchProducts
        let orders = mempty
            productsByProducers = groupProducts products
            customer = newRecord @Customer
            actionUrl = pathTo CreateOrderAction
            unavailable = []
            noProductsSelected = False
        render NewView { .. }

    action ShowOrderAction { orderId } = do
        user <- requirePermission SeeOrders
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
        emailJobs <- query @EmailOrderJob
            |> filterWhere (#orderId, orderId)
            |> orderBy #createdAt
            |> fetch
        let EmailsEnabled emailsEnabled = getAppConfig @EmailsEnabled
        render ShowView { .. }

    action CreateOrderAction = do
        _ <- requirePermission CreateOrders
        producers <- fetchProducers
        products <- fetchProducts
        let actionUrl = pathTo CreateOrderAction
        createOrder actionUrl producers products [] (\_ -> pure ()) \order -> do
            setSuccessMessage "Order created"
            redirectTo ShowOrderAction { orderId = order.id }

    action UpdateMarkPaidOrderAction { orderId } = do
        _ <- requirePermission ManageOrders
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #paidAt now
            |> updateRecord
        setSuccessMessage "Order paid"
        -- Back to the list as it was, with its year, filters and sorting, or
        -- to the order's page when marked there
        redirectBackWithFallback (pathTo OrdersAction)

    action DeleteCancelOrderAction { orderId } = do
        _ <- requirePermission ManageOrders
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #cancelledAt now
            |> updateRecord
        setSuccessMessage "Order cancelled"
        redirectTo OrdersAction

    action UpdateDeliverOrderAction { orderId } = do
        _ <- requirePermission MarkDelivered
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #deliveredAt now
            |> updateRecord
        setSuccessMessage "Order delivered"
        redirectTo ShowOrderAction { orderId }

    action UpdateInvoiceOrderAction { orderId } = do
        _ <- requirePermission ManageOrders
        now <- getCurrentTime
        order <- fetch orderId
        order
            |> setJust #invoicedAt now
            |> updateRecord
        setSuccessMessage "Order invoiced"
        redirectTo ShowOrderAction { orderId }

    -- | Emails the invoice to the customer again, e.g. after their email
    -- address was corrected. The worker sends it, as on ordering.
    action UpdateSendInvoiceOrderAction { orderId } = do
        _ <- requirePermission ManageOrders
        order <- fetch orderId >>= fetchRelated #customerId
        when (isJust order.cancelledAt) do
            setErrorMessage "A cancelled order's invoice can't be sent"
            earlyReturn $ redirectTo ShowOrderAction { orderId }
        _ <- newRecord @EmailOrderJob |> set #orderId orderId |> createRecord
        setSuccessMessage ("Invoice queued for sending to " <> order.customerId.email)
        redirectTo ShowOrderAction { orderId }

    action OrderedProductsAction = do
        _ <- requirePermission SeeOrderedProducts
        (_, ascendingYears) <- queryYears
        let years = reverse ascendingYears
        orderedProductsByYear <- fmap Map.fromList $ forM years $ \year -> do
            let dateAfter = ">= '" <> tshow year <> "-01-01 00:00:00'"
                dateBefore = "< '" <> tshow (year + 1) <> "-01-01 00:00:00'"
            orders <- query @Order
                |> filterWhereSql (#cancelledAt, "IS NULL")
                |> filterWhereSql (#orderedAt, dateAfter)
                |> filterWhereSql (#orderedAt, dateBefore)
                |> fetch
            let orderIds = map (.id) orders
            orderedProducts <- query @OrderedProduct
                |> filterWhereIn (#orderId, orderIds)
                |> fetch
                >>= collectionFetchRelated #productId
            pure (year, orderedProducts)
        let allOrderedProducts = concat (Map.elems orderedProductsByYear)
        xs <- query @Producer
            |> filterWhereIn (#id, map (.productId.producerId) allOrderedProducts)
            |> orderBy #name
            |> fetch
        let producers = sortProducers xs
        render OrderedProductsView { years, orderedProductsByYear, producers }

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
        |> fetch
        |> fmap sortProducers

fetchProducts :: (?modelContext :: ModelContext) => IO [Product]
fetchProducts = do
    query @Product
        |> fetch
