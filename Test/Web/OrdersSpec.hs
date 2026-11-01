module Test.Web.OrdersSpec where

import Network.HTTP.Types (methodGet, methodPost, status200, status404)
import Network.Wai (defaultRequest, requestMethod)
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
