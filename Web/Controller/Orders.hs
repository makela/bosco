module Web.Controller.Orders
    ( fetchShowOrderContext
    , isEmail'
    , isPhone
    ) where

import qualified Network.URI.Encode as E
import qualified Data.Map as Map
import qualified Data.Text as T

import Web.Controller.Prelude
import Web.View.Orders.Index
import Web.View.Orders.New
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
        xs <- query @Producer
            |> orderBy #name
            |> fetch
        let producers = sortProducers xs
        products <- query @Product
            |> orderByDesc #name
            |> fetch
        let orders = mempty
        let productsByProducers = groupProducts products
        let customer = newRecord @Customer
        render NewView { .. }

    action ShowOrderAction { orderId } = do
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
        render ShowView { .. }

    action CreateOrderAction = do
        producers <- query @Producer
            |> orderBy #name
            |> fetch
        products <- query @Product
            |> orderByDesc #name
            |> fetch
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
                                customer <- customer |> createRecord
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
                                setSuccessMessage "Tilaus tallennettu"
                                redirectTo ShowOrderAction { orderId = order.id }

    action CancelOrderAction { orderId } = do
        order <- fetch orderId
        now <- getCurrentTime
        order |> setJust #cancelledAt now |> updateRecord
        setSuccessMessage "Tilaus peruttu"
        redirectTo OrdersAction

buildCustomer customer = customer
    |> fill @["name","email","phone","address"]
    |> validateField #email isEmail'
    |> validateField #phone isPhone
    |> validateField #address nonEmpty

isEmail' :: Text -> ValidatorResult
isEmail' text = case isEmail text of
    Success -> Success
    Failure _ -> Failure "Sähköposti on virheellinen"
    FailureHtml x -> FailureHtml x

isPhone :: Text -> ValidatorResult
isPhone text | ("+" `isPrefixOf` text) && (T.length text) == 13 = Success
isPhone text | ("0" `isPrefixOf` text) && (T.length text) == 10 = Success
isPhone text = Failure "Puhelinnumero on virheellinen"

buildOrder order = order
    |> fill @'["customerId"]
    -- TODO validate the order, empty orders are worth of nothing

groupProducts :: [Product] -> ProductsByProducers
groupProducts products = go products mempty
    where go [] m = m
          go (x:xs) m = go xs (Map.insertWith (++) x.producerId [x] m)

groupOrderedProducts :: [Include "productId" OrderedProduct] -> OrderedProductsByProducer
groupOrderedProducts orderedProducts = go orderedProducts mempty
    where go [] m = m
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
