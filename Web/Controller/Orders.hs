module Web.Controller.Orders
    ( createOrder
    , countSum
    , fetchShowOrderContext
    , groupOrderedProducts
    , groupProducts
    , isEmail'
    , isPhone
    , sortProducers
    ) where

import qualified Data.Map as Map
import qualified Data.Text as T
import qualified Network.URI.Encode as E

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
        unless (maybe False (.isOrderingEnabled) message) renderNotFound
        xs <- fetchProducers
        let producers = sortProducers xs
        products <- fetchProducts
        let orders = mempty
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
        unless (maybe False (.isOrderingEnabled) message) (redirectTo OrdersAction)
        producers <- fetchProducers
        products <- fetchProducts
        let actionUrl = pathTo CreateOrderAction
        createOrder actionUrl producers products $ \order -> do
            setSuccessMessage "Tilaus lähetetty"
            let email = newRecord @EmailOrderJob
            email
                |> set #orderId order.id
                |> createRecord
            redirectTo ShowOrderAction { orderId = order.id }

    action UpdateCancelOrderAction { orderId } = do
        order <- fetch orderId
        now <- getCurrentTime
        order |> setJust #cancelledAt now |> updateRecord
        setSuccessMessage "Tilaus peruttu"
        redirectTo OrdersAction

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
                    let reverseName = toLower . unwords . reverse $ words customer.name
                    customer <- customer
                        |> set #reverseName reverseName
                        |> createRecord
                    setSuccessMessage "Tiedot tallennettu"
                    redirectTo OrdersAction

buildCustomer customer = customer
    |> fill @["name","email","phone","address"]
    |> validateField #name nonEmptyOrWhitespace
    |> validateField #email isEmail'
    |> validateField #phone isPhone
    |> validateField #address nonEmptyOrWhitespace

buildEmail customer = customer
    |> fill @["name","email"]
    |> validateField #name nonEmptyOrWhitespace
    |> validateField #email isEmail'

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

isPhone :: Text -> ValidatorResult
isPhone text
    | ("+" `isPrefixOf` text) && l > 9 && l < 14 && onlyNumbers = Success
    -- allow country code even without missing +
    | ("3" `isPrefixOf` text) && l > 8 && l < 13 && onlyNumbers = Success
    | ("0" `isPrefixOf` text) && l > 6 && l < 11 && onlyNumbers = Success
    | otherwise = Failure "Puhelinnumero on virheellinen"
    where
        l = T.length $ T.filter (' ' /=) text
        validChars = "+0123456789 " :: String
        onlyNumbers = T.all (`elem` validChars) text

buildOrder order = order
    |> fill @'["customerId"]
    -- TODO validate the order, empty orders are worth of nothing

fetchProducers :: (?modelContext :: ModelContext) =>IO [Producer]
fetchProducers = do
    query @Producer
        |> filterWhere (#enabled, True)
        |> orderByDesc #name
        |> fetch

fetchProducts :: (?modelContext :: ModelContext) =>IO [Product]
fetchProducts = do
    query @Product
        |> filterWhere (#enabled, True)
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
    |> map (\x -> x.productId.price * x.quantity)
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
    -- TODO We should fix total price at ordering, because prices can change
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

createOrder :: (?context::ControllerContext, ?modelContext::ModelContext, ?respond::Respond, ?request::Request) => Text -> [Producer] -> [Product] -> (Order -> IO ()) -> IO ()
createOrder actionUrl producers products after = do
    let params = products
            |> map (\x -> (x.id, paramOrDefault @Int 0 (x.id |> show |> E.encodeTextToBS)))
            |> filter (\(_, i) -> i > 0)
    let orders = Map.fromList params
    let productsByProducers = groupProducts products
    -- TODO if Map.isEmpty orders then render NewView { .. } else
    -- TODO save valid customer information for later use
    -- TODO match existing customer
    let customer = newRecord @Customer
    customer
        |> buildCustomer
        |> ifValid \case
            Left customer -> do
                render NewView { .. }
            Right customer -> do
                let order = newRecord @Order
                order
                    |> buildOrder
                    |> ifValid \case
                        Left order -> do
                            render NewView { .. }
                        Right order -> do
                            -- TODO transaction
                            let reverseName = toLower . unwords . reverse $ words customer.name
                            customer <- customer
                                |> set #reverseName reverseName
                                |> createRecord
                            order <- order
                                |> set #customerId customer.id
                                |> createRecord
                            let orders = params
                                    |> map (\(pid, count) ->
                                          newRecord @OrderedProduct
                                              |> set #orderId order.id
                                              |> set #productId pid
                                              |> set #quantity count)
                            forM_ orders createRecord
                            after order
