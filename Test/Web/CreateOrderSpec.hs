module Test.Web.CreateOrderSpec where

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
submitOrder email quantities = callActionWithParams CreateOrderAction $
    [ ("name", "Maija Virtanen")
    , ("email", cs email)
    , ("phone", "0401234567")
    , ("address", "Testikatu 1")
    ] <> map (\(product, n) -> (idToParam product.id, cs (tshow n))) quantities

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
