module Test.Web.OrdersSpec where

import Network.HTTP.Types (status200, status302, status404)
import Network.Wai.Test (SResponse (..))

import IHP.ControllerPrelude
import IHP.Hspec (withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Config
import Generated.Types
import Web.Types

import Test.App

tests :: Spec
tests = aroundAll (withIHPApp WebApplication config) do
    describe "Web OrdersController" do
        it "serves an order's page by its id (routing sanity check)" $ withContext do
            order <- createTestOrder "Maija Virtanen"
            response <- inApp $ httpGet ("/ShowOrder?orderId=" <> idToParam order.id)
            simpleStatus response `shouldBe` status200
            bodyText response `shouldSatisfy` ("Maija Virtanen" `isInfixOf`)

        it "says on the invoice when it has been paid or cancelled" $ withContext do
            now <- getCurrentTime
            paid <- createTestOrder "Paid Customer" >>= \o -> o |> setJust #paidAt now |> updateRecord
            cancelled <- createTestOrder "Cancelled Customer" >>= \o -> o |> setJust #cancelledAt now |> updateRecord
            paidPage <- inApp $ httpGet ("/ShowOrder?orderId=" <> idToParam paid.id)
            bodyText paidPage `shouldSatisfy` ("Lasku on maksettu." `isInfixOf`)
            cancelledPage <- inApp $ httpGet ("/ShowOrder?orderId=" <> idToParam cancelled.id)
            bodyText cancelledPage `shouldSatisfy` ("Lasku on mitätöity." `isInfixOf`)

        it "has no public route that cancels an order" $ withContext do
            order <- createTestOrder "Ville Korhonen"
            response <- inApp $ httpPost ("/UpdateCancelOrder?orderId=" <> idToParam order.id) []
            simpleStatus response `shouldBe` status404
            order' <- fetch order.id
            order'.cancelledAt `shouldBe` Nothing

        it "tells the customer when ordering closed before they sent the order" $ withContext do
            _ <- newRecord @WelcomeMessage
                |> set #text "Tilaukset on suljettu"
                |> set #isOrderingEnabled False
                |> createRecord
            (submitted, frontPage) <- inApp do
                submitted <- httpPost "/CreateOrder"
                    [ ("name", "Late Customer")
                    , ("email", "late@example.com")
                    , ("phone", "0401234567")
                    , ("address", "Testikatu 1")
                    ]
                frontPage <- followRedirect submitted
                pure (submitted, frontPage)
            simpleStatus submitted `shouldBe` status302
            lookup "Location" (simpleHeaders submitted) `shouldBe` Just "http://localhost/Orders"
            simpleStatus frontPage `shouldBe` status200
            bodyText frontPage `shouldSatisfy` ("Tilaustasi ei lähetetty, koska tilaukset on suljettu" `isInfixOf`)
            count <- query @Customer |> filterWhere (#email, "late@example.com") |> fetchCount
            count `shouldBe` 0

        it "sends an order form link opened while ordering is closed to the front page" $ withContext do
            _ <- newRecord @WelcomeMessage
                |> set #text "Tilaukset on suljettu"
                |> set #isOrderingEnabled False
                |> createRecord
            (opened, frontPage) <- inApp do
                opened <- httpGet "/NewOrder"
                frontPage <- followRedirect opened
                pure (opened, frontPage)
            simpleStatus opened `shouldBe` status302
            lookup "Location" (simpleHeaders opened) `shouldBe` Just "http://localhost/Orders"
            simpleStatus frontPage `shouldBe` status200
            bodyText frontPage `shouldSatisfy` ("Tilaaminen ei ole tällä hetkellä mahdollista" `isInfixOf`)

createTestOrder :: (?modelContext :: ModelContext) => Text -> IO Order
createTestOrder name = do
    customer <- newRecord @Customer
        |> set #name name
        |> set #email "test@example.com"
        |> set #phone "0401234567"
        |> set #address "Testikatu 1"
        |> createRecord
    newRecord @Order
        |> set #customerId customer.id
        |> createRecord
