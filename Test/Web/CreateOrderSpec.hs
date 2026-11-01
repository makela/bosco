module Test.Web.CreateOrderSpec where

import Network.HTTP.Types (status200)

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

submitOrder email quantities = callActionWithParams CreateOrderAction $
    [ ("name", "Maija Virtanen")
    , ("email", email)
    , ("phone", "0401234567")
    , ("address", "Testikatu 1")
    ] <> map (\(product, n) -> (idToParam product.id, cs (tshow n))) quantities

-- | What got ordered by the customer with this email, if anything.
orderedQuantities :: (?modelContext :: ModelContext) => Text -> IO [(Id Product, Int)]
orderedQuantities email = do
    customers <- query @Customer |> filterWhere (#email, email) |> fetch
    orders <- query @Order |> filterWhereIn (#customerId, map (.id) customers) |> fetch
    ordered <- query @OrderedProduct |> filterWhereIn (#orderId, map (.id) orders) |> fetch
    pure $ map (\x -> (x.productId, x.quantity)) ordered
