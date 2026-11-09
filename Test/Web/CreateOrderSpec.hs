module Test.Web.CreateOrderSpec where

import qualified Control.Exception as Exception
import qualified Data.Text as T
import Network.HTTP.Types (status200)
import Network.Wai (Response)

import IHP.ControllerPrelude
import IHP.Hspec (responseBodyShouldContain, responseBodyShouldNotContain,
                  responseStatusShouldBe, withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Config
import Generated.Types
import Web.Controller.Orders ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = aroundAll (withIHPApp WebApplication config) do
    describe "Web CreateOrderAction with products that became unavailable" do
        it "creates the order when everything is still available" $ withContext do
            (_, oil, honey) <- setUp "ok"
            _ <- submitOrder "ok@example.com" [(oil, 2), (honey, 1)]
            quantities <- orderedQuantities "ok@example.com"
            sort quantities `shouldBe` sort [(oil.id, 2), (honey.id, 1)]

        it "refuses the order when an ordered product was disabled" $ withContext do
            (_, oil, honey) <- setUp "product"
            oil |> set #enabled False |> updateRecord
            response <- submitOrder "product@example.com" [(oil, 2), (honey, 1)]
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "eivät ole enää tilattavissa"
            response `responseBodyShouldContain` "Testiöljy product"
            orderedQuantities "product@example.com" `shouldReturn` []

        it "refuses the order when an ordered product's producer was disabled" $ withContext do
            (producer, oil, honey) <- setUp "producer"
            producer |> set #enabled False |> updateRecord
            response <- submitOrder "producer@example.com" [(oil, 2), (honey, 1)]
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "eivät ole enää tilattavissa"
            response `responseBodyShouldContain` "Testiöljy producer"
            response `responseBodyShouldContain` "Testihunaja producer"
            orderedQuantities "producer@example.com" `shouldReturn` []

        it "keeps the customer's details and the other quantities in the form" $ withContext do
            (_, oil, honey) <- setUp "kept"
            oil |> set #enabled False |> updateRecord
            response <- submitOrder "kept@example.com" [(oil, 2), (honey, 3)]
            response `responseBodyShouldContain` "value=\"kept@example.com\""
            response `responseBodyShouldContain` "value=\"Testikatu 1\""
            response `responseBodyShouldContain` ("name=\"" <> tshow honey.id <> "\" value=\"3\"")

        it "does not complain about a disabled product that was not ordered" $ withContext do
            (_, oil, honey) <- setUp "unordered"
            oil |> set #enabled False |> updateRecord
            response <- submitOrder "unordered@example.com" [(honey, 1)]
            response `responseBodyShouldNotContain` "eivät ole enää tilattavissa"
            orderedQuantities "unordered@example.com" `shouldReturn` [(honey.id, 1)]

    describe "Web CreateOrderAction without products" do
        it "refuses an order with no products" $ withContext do
            _ <- setUp "empty"
            response <- submitOrder "empty@example.com" []
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Valitse vähintään yksi tuote"
            response `responseBodyShouldContain` "value=\"empty@example.com\""
            customerCount "empty@example.com" `shouldReturn` 0

        it "refuses an order where every quantity is zero" $ withContext do
            (_, oil, honey) <- setUp "zero"
            response <- submitOrder "zero@example.com" [(oil, 0), (honey, 0)]
            response `responseBodyShouldContain` "Valitse vähintään yksi tuote"
            customerCount "zero@example.com" `shouldReturn` 0

        it "asks only about unavailable products when those were all that was ordered" $ withContext do
            (_, oil, _) <- setUp "only unavailable"
            oil |> set #enabled False |> updateRecord
            response <- submitOrder "onlyunavailable@example.com" [(oil, 1)]
            response `responseBodyShouldContain` "eivät ole enää tilattavissa"
            response `responseBodyShouldNotContain` "Valitse vähintään yksi tuote"

    describe "Web CreateOrderAction saving" do
        it "saves nothing when saving an order line fails" $ withContext do
            (_, oil, honey) <- setUp "transaction"
            ordersBefore <- query @Order |> fetchCount
            jobsBefore <- query @EmailOrderJob |> fetchCount
            -- Make the second step of saving fail: order lines with quantity 13
            let failLines = sqlExecDiscardResult "ALTER TABLE ordered_products ADD CONSTRAINT test_fail_lines CHECK (quantity <> 13)" ()
                allowLines = sqlExecDiscardResult "ALTER TABLE ordered_products DROP CONSTRAINT test_fail_lines" ()
            _ <- Exception.bracket_ failLines allowLines do
                Exception.try @Exception.SomeException (submitOrder "transaction@example.com" [(oil, 1), (honey, 13)])
            customerCount "transaction@example.com" `shouldReturn` 0
            (query @Order |> fetchCount) `shouldReturn` ordersBefore
            (query @EmailOrderJob |> fetchCount) `shouldReturn` jobsBefore

        it "saves the customer, order, lines and email job together" $ withContext do
            (_, oil, _) <- setUp "saved"
            _ <- submitOrder "saved@example.com" [(oil, 1)]
            order <- orderOf "saved@example.com"
            orderedQuantities "saved@example.com" `shouldReturn` [(oil.id, 1)]
            jobs <- query @EmailOrderJob |> filterWhere (#orderId, order.id) |> fetchCount
            jobs `shouldBe` 1

    describe "Web CreateOrderAction customer details" do
        it "saves the name and address in their parts, and shows them on the invoice" $ withContext do
            (_, oil, _) <- setUp "parts"
            _ <- submitOrderWith "parts@example.com"
                [("firstName", " Anna-Liisa "), ("streetAddress", "Kotitie 12 B 4"), ("postalCode", "33100"), ("city", "Tampere")]
                [(oil, 1)]
            customer <- query @Customer |> filterWhere (#email, "parts@example.com") |> fetchOne
            (customer.firstName, customer.lastName, customer.reverseName) `shouldBe` ("Anna-Liisa", "Virtanen", "virtanen anna-liisa")
            (customer.streetAddress, customer.postalCode, customer.city) `shouldBe` ("Kotitie 12 B 4", "33100", "Tampere")
            order <- orderOf "parts@example.com"
            invoice <- callAction ShowOrderAction { orderId = order.id }
            invoice `responseBodyShouldContain` "<p>Anna-Liisa Virtanen</p>"
            invoice `responseBodyShouldContain` "<p>Kotitie 12 B 4</p>"
            invoice `responseBodyShouldContain` "<p>33100 Tampere</p>"
            invoice `responseBodyShouldNotContain` "<p></p>"

        it "saves the name for the invoice and shows it above the customer's name" $ withContext do
            (_, oil, _) <- setUp "billing"
            _ <- submitOrderWith "billing@example.com" [("billingName", " Oliivi Oy, 1234567-8 ")] [(oil, 1)]
            customer <- query @Customer |> filterWhere (#email, "billing@example.com") |> fetchOne
            customer.billingName `shouldBe` "Oliivi Oy, 1234567-8"
            order <- orderOf "billing@example.com"
            invoice <- callAction ShowOrderAction { orderId = order.id }
            invoice `responseBodyShouldContain` "<p>Oliivi Oy, 1234567-8</p><p>Maija Virtanen</p>"

        it "accepts an order without a last name" $ withContext do
            (_, oil, _) <- setUp "one name"
            _ <- submitOrderWith "onename@example.com" [("lastName", "")] [(oil, 1)]
            orderedQuantities "onename@example.com" `shouldReturn` [(oil.id, 1)]

        forM_ [("streetAddress", ""), ("postalCode", ""), ("postalCode", "1234"), ("postalCode", "00100 Helsinki"), ("city", " ")] \(field, value) ->
            it (cs ("refuses an order with " <> cs field <> " " <> tshow value)) $ withContext do
                (_, oil, _) <- setUp ("refused " <> cs field <> cs value)
                let email = "refused" <> cs field <> T.filter (/= ' ') (cs value) <> "@example.com"
                response <- submitOrderWith email [(field, value)] [(oil, 1)]
                response `responseStatusShouldBe` status200
                customerCount email `shouldReturn` 0

    describe "Web producer order" do
        it "lists producers the same way on the order form and the invoice" $ withContext do
            _ <- setUp "producer order"
            let fixtureProducers = ["Bosco Falconeria", "Bonomo & Giglio", "Lorcam", "Quetzal", "Stramondo", "Valdibella"]
                -- First words only: the page escapes "&" as "&amp;"
                shownAs = map (fromMaybe "" . head . T.words) fixtureProducers
                appearsInOrder body = let positions = map (\name -> fst (T.breakOn name body)) shownAs
                                      in map T.length positions == sort (map T.length positions)
                                         && all (`T.isInfixOf` body) shownAs
            form <- callAction NewOrderAction
            formBody <- cs <$> responseBody form
            formBody `shouldSatisfy` appearsInOrder
            -- One product from each fixture producer
            producers <- query @Producer |> fetch
            ordered <- forM (filter (\p -> p.name `elem` fixtureProducers) producers) \p ->
                query @Product |> filterWhere (#producerId, p.id) |> fetchOne
            _ <- submitOrder "producerorder@example.com" (map (\x -> (x, 1)) ordered)
            order <- orderOf "producerorder@example.com"
            invoice <- callAction ShowOrderAction { orderId = order.id }
            invoiceBody <- cs <$> responseBody invoice
            invoiceBody `shouldSatisfy` appearsInOrder

    describe "Web order prices" do
        it "keeps the price the order was placed at when the product's price changes" $ withContext do
            (_, oil, _) <- setUp "price"
            _ <- submitOrder "price@example.com" [(oil, 2)]
            oil |> set #price 1500 |> updateRecord
            order <- orderOf "price@example.com"
            response <- callAction ShowOrderAction { orderId = order.id }
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "20 €"
            response `responseBodyShouldNotContain` "15 €"
            response `responseBodyShouldNotContain` "30 €"
            ordered <- query @OrderedProduct |> filterWhere (#orderId, order.id) |> fetchOne
            ordered.unitPrice `shouldBe` 1000

-- | Opens ordering and creates a fresh producer with two products. Tests
-- share one database, so the tag keeps their product names apart.
setUp :: (?modelContext :: ModelContext) => Text -> IO (Producer, Product, Product)
setUp tag = do
    _ <- newRecord @WelcomeMessage
        |> set #text "Tervetuloa"
        |> set #isOrderingEnabled True
        |> createRecord
    producer <- newRecord @Producer
        |> set #name ("Testitila " <> tag)
        |> set #subject ""
        |> set #description ""
        |> createRecord
    let product name = newRecord @Product
            |> set #producerId producer.id
            |> set #name (name <> " " <> tag)
            |> set #description ""
            |> set #package "1 l"
            |> set #price 1000
            |> createRecord
    oil <- product "Testiöljy"
    honey <- product "Testihunaja"
    pure (producer, oil, honey)

submitOrder :: (ContextParameters WebApplication) => Text -> [(Product, Int)] -> IO Response
submitOrder email = submitOrderWith email []

-- | An order with some of the customer's fields replaced
submitOrderWith :: (ContextParameters WebApplication) => Text -> [(ByteString, ByteString)] -> [(Product, Int)] -> IO Response
submitOrderWith email replaced quantities = callActionWithParams CreateOrderAction $
    map (\(k, v) -> (k, fromMaybe v (lookup k replaced)))
        [ ("firstName", "Maija")
        , ("lastName", "Virtanen")
        , ("billingName", "")
        , ("email", cs email)
        , ("phone", "0401234567")
        , ("streetAddress", "Testikatu 1")
        , ("postalCode", "00100")
        , ("city", "Helsinki")
        ]
    <> map (\(product, n) -> (idToParam product.id, cs (tshow n))) quantities

customerCount :: (?modelContext :: ModelContext) => Text -> IO Int
customerCount email = query @Customer |> filterWhere (#email, email) |> fetchCount

orderOf :: (?modelContext :: ModelContext) => Text -> IO Order
orderOf email = do
    customer <- query @Customer |> filterWhere (#email, email) |> fetchOne
    query @Order |> filterWhere (#customerId, customer.id) |> fetchOne

-- | What got ordered by the customer with this email, if anything.
orderedQuantities :: (?modelContext :: ModelContext) => Text -> IO [(Id Product, Int)]
orderedQuantities email = do
    customers <- query @Customer |> filterWhere (#email, email) |> fetch
    orders <- query @Order |> filterWhereIn (#customerId, map (.id) customers) |> fetch
    ordered <- query @OrderedProduct |> filterWhereIn (#orderId, map (.id) orders) |> fetch
    pure $ map (\x -> (x.productId, x.quantity)) ordered
