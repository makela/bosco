module Web.Controller.Orders
    ( createOrder
    , countSum
    , fetchShowOrderContext
    , groupOrderedProducts
    , groupProducts
    , isEmail'
    , nonEmptyOrWhitespace
    , setReverseName
    , sortProducers
    ) where

import qualified Data.Map as Map
import qualified Data.Text as T
import qualified Network.URI.Encode as E

import Application.Localization
import Web.Controller.Prelude hiding (createOrder)
import Web.Mail.Orders.Order
import Web.View.Orders.Index
import Web.View.Orders.New
import Web.View.Orders.NewEmail
import Web.View.Orders.Show

instance Controller OrdersController where
    action OrdersAction = do
        message <- fetchLastWelcomeMessage
        now <- getCurrentTime
        let publishedAt = maybe now (get #publishedAt) message
            (y, _, _) = toGregorian $ utctDay publishedAt
            year = show y
        render IndexView { .. }

    action NewOrderAction = do
        message <- fetchLastWelcomeMessage
        -- Old links to the order form keep working after ordering closes
        unless (maybe False (.isOrderingEnabled) message) do
            setErrorMessage (l10nText LOrderingNotOpen)
            earlyReturn $ redirectTo OrdersAction
        xs <- fetchProducers
        let producers = sortProducers xs
        products <- fetchProducts producers
        let orders = mempty
            unavailable = []
            noProductsSelected = False
        let productsByProducers = groupProducts products
        let customer = newRecord @Customer
        let actionUrl = pathTo CreateOrderAction
        render NewView { .. }

    action ShowOrderAction { orderId } = do
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
        paymentInstruction <- query @PaymentInstruction |> orderByDesc #publishedAt |> fetchOneOrNothing
        render ShowView { .. }

    action CreateOrderAction = do
        message <- fetchLastWelcomeMessage
        -- Ordering can close while the customer is still filling in the form
        unless (maybe False (.isOrderingEnabled) message) do
            setErrorMessage (l10nText LOrderingClosed)
            earlyReturn $ redirectTo OrdersAction
        producers <- fetchProducers
        products <- fetchProducts producers
        allProducts <- query @Product |> fetch
        let orderable = map (.id) products
            unorderable = filter (\x -> x.id `notElem` orderable) allProducts
            actionUrl = pathTo CreateOrderAction
        let queueEmail order = do
                _ <- newRecord @EmailOrderJob |> set #orderId order.id |> createRecord
                pure ()
        createOrder actionUrl producers products unorderable queueEmail \order -> do
            setSuccessMessage "Tilaus lähetetty"
            redirectTo ShowOrderAction { orderId = order.id }

    action NewEmailAction = do
        let customer = newRecord @Customer
        render NewEmailView { .. }

    action CreateEmailAction = do
        let customer = newRecord @Customer
        customer
            |> buildEmail
            |> ifValid \case
                Left customer -> do
                    render NewEmailView { .. }
                Right customer -> do
                    _ <- customer |> createRecord
                    setSuccessMessage "Tiedot tallennettu"
                    redirectTo OrdersAction

buildCustomer customer = customer
    |> fill @["name","email","phone","address"]
    |> validateField #name nonEmptyOrWhitespace
    |> validateField #email isEmail'
    |> validateField #phone isPhone
    |> validateField #address nonEmptyOrWhitespace
    |> setReverseName

buildEmail customer = customer
    |> fill @["name","email"]
    |> validateField #name nonEmptyOrWhitespace
    |> validateField #email isEmail'
    |> setReverseName

setReverseName :: Customer -> Customer
setReverseName customer = customer |> set #reverseName (reverseNameOf customer.name)

nonEmptyOrWhitespace :: Text -> ValidatorResult
nonEmptyOrWhitespace text = case nonEmpty $ T.strip text of
    Success       -> Success
    Failure _     -> Failure "Tämä kenttä vaaditaan"
    FailureHtml x -> FailureHtml x

isEmail' :: Text -> ValidatorResult
isEmail' text = case isEmail text of
    Success       -> Success
    Failure _     -> Failure "Sähköposti on virheellinen"
    FailureHtml x -> FailureHtml x

buildOrder order = order
    |> fill @'["customerId"]

fetchProducers :: (?modelContext :: ModelContext) =>IO [Producer]
fetchProducers = do
    query @Producer
        |> filterWhere (#enabled, True)
        |> orderByDesc #name
        |> fetch

-- | Products that can be ordered: enabled, from one of the given producers.
fetchProducts :: (?modelContext :: ModelContext) => [Producer] -> IO [Product]
fetchProducts producers = do
    query @Product
        |> filterWhere (#enabled, True)
        |> filterWhereIn (#producerId, map (.id) producers)
        |> orderByDesc #ordering
        |> orderByDesc #name
        |> fetch

groupProducts :: [Product] -> ProductsByProducers
groupProducts products = go products mempty
    where go [] m     = m
          go (x:xs) m = go xs (Map.insertWith (++) x.producerId [x] m)

groupOrderedProducts :: [Include "productId" OrderedProduct] -> OrderedProductsByProducer
groupOrderedProducts orderedProducts = go orderedProducts mempty
    where go [] m     = m
          go (x:xs) m = go xs (Map.insertWith (++) x.productId.producerId [x] m)

sortProducers :: [Producer] -> [Producer]
sortProducers xs = filter isBosco xs ++ filter (not . isBosco) xs

isBosco :: Producer -> Bool
isBosco x = x.name == "Bosco Falconeria"

countSum xs = xs
    |> map (\x -> x.unitPrice * x.quantity)
    |> sum

fetchShowOrderContext :: (?modelContext :: ModelContext)
                      => Id Order
                      -> IO ( Include "customerId" Order
                            , Int
                            , OrderedProductsByProducer
                            , [Producer]
                            )
fetchShowOrderContext orderId = do
    order <- fetch orderId >>= fetchRelated #customerId
    xs <- query @OrderedProduct
        |> filterWhere (#orderId, orderId)
        |> fetch
        >>= collectionFetchRelated #productId
    let totalSum = countSum xs
    let orderedProductsByProducer = groupOrderedProducts xs
    xs <- query @Producer
        |> filterWhereIn (#id, Map.keys orderedProductsByProducer)
        |> orderBy #name
        |> fetch
    let producers = sortProducers xs
    return (order, totalSum, orderedProductsByProducer, producers)

fetchLastWelcomeMessage :: (?modelContext :: ModelContext) => IO (Maybe WelcomeMessage)
fetchLastWelcomeMessage = query @WelcomeMessage |> orderByDesc #publishedAt |> fetchOneOrNothing

-- | Saves the order for the given products. If any of the unorderable
-- products were ordered too (they were disabled while the customer filled
-- in the form), or no products were ordered at all, nothing is saved and
-- the form says why.
--
-- The customer, the order, its lines and whatever @onSaved@ saves (e.g. the
-- email job) are saved in one transaction: all of them or none.
createOrder :: (?context::ControllerContext, ?modelContext::ModelContext, ?respond::Respond, ?request::Request) => Text -> [Producer] -> [Product] -> [Product] -> ((?modelContext::ModelContext) => Order -> IO ()) -> (Order -> IO ResponseReceived) -> IO ResponseReceived
createOrder actionUrl producers products unorderable onSaved after = do
    let quantityOf x = paramOrDefault @Int 0 (x.id |> show |> E.encodeTextToBS)
    let params = products
            |> map (\x -> (x, quantityOf x))
            |> filter (\(_, i) -> i > 0)
    let unavailable = filter (\x -> quantityOf x > 0) unorderable
    -- Only one notice at a time: unavailable products explain an empty order
    let noProductsSelected = null params && null unavailable
    let orders = Map.fromList (map (\(x, i) -> (x.id, i)) params)
    let productsByProducers = groupProducts products
    -- TODO save valid customer information for later use
    -- TODO match existing customer
    let customer = newRecord @Customer
    customer
        |> buildCustomer
        |> ifValid \case
            Left customer -> do
                render NewView { .. }
            Right customer | not (null unavailable) || noProductsSelected -> do
                render NewView { .. }
            Right customer -> do
                let order = newRecord @Order
                order
                    |> buildOrder
                    |> ifValid \case
                        Left order -> do
                            render NewView { .. }
                        Right order -> do
                            order <- withTransaction do
                                customer <- customer |> createRecord
                                order <- order
                                    |> set #customerId customer.id
                                    |> createRecord
                                let orders = params
                                        |> map (\(product, count) ->
                                              newRecord @OrderedProduct
                                                  |> set #orderId order.id
                                                  |> set #productId product.id
                                                  |> set #quantity count
                                                  -- Fixed now, so later price changes don't touch this order
                                                  |> set #unitPrice product.price)
                                forM_ orders createRecord
                                onSaved order
                                pure order
                            after order
