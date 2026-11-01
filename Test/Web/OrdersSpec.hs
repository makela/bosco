module Test.Web.OrdersSpec where

import Network.HTTP.Types (hContentType, methodGet, methodPost, status200,
                          status302, status404)
import Network.HTTP.Types.URI (renderSimpleQuery)
import Network.Wai (defaultRequest, requestHeaders, requestMethod)
import Network.Wai.Test (SRequest (..), SResponse (..), runSession, setPath,
                         srequest)

import IHP.ControllerPrelude
import IHP.FrameworkConfig (RootApplication (..))
import IHP.Hspec (withIHPApp)
import IHP.RouterSupport (FrontController (..), mountFrontController)
import IHP.Test.Mocking
import Test.Hspec

import Admin.FrontController ()
import Admin.Types (AdminApplication (..))
import Config
import Generated.Types
import Web.FrontController ()
import Web.Types

-- Same mounts as Main.hs. Main can't be imported from a test (both are
-- module Main), so the routing tests rebuild the root application here.
instance FrontController RootApplication where
    controllers =
        [ mountFrontController WebApplication
        , mountFrontController AdminApplication
        ]

tests :: Spec
tests = aroundAll (withIHPApp WebApplication config) do
    describe "Web OrdersController" do
        it "serves an order's page by its id (routing sanity check)" $ withContext do
            order <- createTestOrder "Maija Virtanen"
            response <- sendRequest methodGet ("/ShowOrder?orderId=" <> idToParam order.id)
            simpleStatus response `shouldBe` status200
            cs (simpleBody response) `shouldSatisfy` ("Maija Virtanen" `isInfixOf`)

        it "has no public route that cancels an order" $ withContext do
            order <- createTestOrder "Ville Korhonen"
            response <- sendRequest methodPost ("/UpdateCancelOrder?orderId=" <> idToParam order.id)
            simpleStatus response `shouldBe` status404
            order' <- fetch order.id
            order'.cancelledAt `shouldBe` Nothing

        it "tells the customer when ordering closed before they sent the order" $ withContext do
            _ <- newRecord @WelcomeMessage
                |> set #text "Tilaukset on suljettu"
                |> set #isOrderingEnabled False
                |> createRecord
            app <- initTestApplication ?mocking
            -- One session, so the flash cookie from the POST reaches the next page
            (submitted, frontPage) <- flip runSession app do
                submitted <- srequest $ SRequest
                    (setPath defaultRequest
                        { requestMethod = methodPost
                        , requestHeaders = [(hContentType, "application/x-www-form-urlencoded")]
                        } "/CreateOrder")
                    (cs $ renderSimpleQuery False
                        [ ("name", "Late Customer")
                        , ("email", "late@example.com")
                        , ("phone", "0401234567")
                        , ("address", "Testikatu 1")
                        ])
                -- Follow the redirect like a browser would
                frontPage <- srequest (SRequest (setPath defaultRequest "/Orders") "")
                pure (submitted, frontPage)
            simpleStatus submitted `shouldBe` status302
            lookup "Location" (simpleHeaders submitted) `shouldBe` Just "http://localhost/Orders"
            simpleStatus frontPage `shouldBe` status200
            cs (simpleBody frontPage) `shouldSatisfy` ("Tilaustasi ei lähetetty, koska tilaukset on suljettu" `isInfixOf`)
            count <- query @Customer |> filterWhere (#email, "late@example.com") |> fetchCount
            count `shouldBe` 0

        it "sends an order form link opened while ordering is closed to the front page" $ withContext do
            _ <- newRecord @WelcomeMessage
                |> set #text "Tilaukset on suljettu"
                |> set #isOrderingEnabled False
                |> createRecord
            app <- initTestApplication ?mocking
            (opened, frontPage) <- flip runSession app do
                opened <- srequest (SRequest (setPath defaultRequest "/NewOrder") "")
                frontPage <- srequest (SRequest (setPath defaultRequest "/Orders") "")
                pure (opened, frontPage)
            simpleStatus opened `shouldBe` status302
            lookup "Location" (simpleHeaders opened) `shouldBe` Just "http://localhost/Orders"
            simpleStatus frontPage `shouldBe` status200
            cs (simpleBody frontPage) `shouldSatisfy` ("Tilaaminen ei ole tällä hetkellä mahdollista" `isInfixOf`)

-- | Sends an unauthenticated request through the full app, router included.
sendRequest method path = do
    app <- initTestApplication ?mocking
    let req = setPath defaultRequest { requestMethod = method } path
    runSession (srequest (SRequest req "")) app

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
