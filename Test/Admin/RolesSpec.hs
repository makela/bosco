module Test.Admin.RolesSpec where

import qualified Control.Exception as Exception
import Network.HTTP.Types (status200, status403)
import Network.Wai (Response, responseStatus)

import IHP.ControllerPrelude
import IHP.Hspec (responseBodyShouldContain, responseBodyShouldNotContain,
                  responseStatusShouldBe, withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.Controller.Customers ()
import Admin.Controller.Orders ()
import Admin.Controller.Producers ()
import Admin.Controller.Products ()
import Admin.Controller.Static ()
import Admin.FrontController ()
import Admin.Types
import Config
import Generated.Types

import Test.Admin.Users (createDeliverer, createPromoter, createUserWithRoles)

tests :: Spec
tests = aroundAll (withIHPApp AdminApplication config) do
    describe "Admin roles: a delivery person" do
        it "marks an order delivered but not invoiced or paid" $ withContext do
            user <- createDeliverer
            order <- createRoleOrder "deliverer@example.com"
            page <- withUser user $ callAction ShowOrderAction { orderId = order.id }
            page `responseBodyShouldContain` "Mark as delivered"
            page `responseBodyShouldNotContain` "Mark as invoiced"
            page `responseBodyShouldNotContain` "Mark as paid"
            _ <- withUser user $ callAction UpdateDeliverOrderAction { orderId = order.id }
            denied (withUser user $ callAction UpdateInvoiceOrderAction { orderId = order.id }) `shouldReturn` True
            denied (withUser user $ callAction UpdateMarkPaidOrderAction { orderId = order.id }) `shouldReturn` True
            order' <- fetch order.id
            (isJust order'.deliveredAt, order'.invoicedAt, order'.paidAt) `shouldBe` (True, Nothing, Nothing)

        it "doesn't see the email lists" $ withContext do
            user <- createDeliverer
            denied (withUser user $ callAction EmailsForNewsLetterAction) `shouldReturn` True
            denied (withUser user $ callAction EmailsForDeliveryInfoAction) `shouldReturn` True
            menu <- withUser user $ callAction WelcomeAction
            menu `responseBodyShouldNotContain` "Emails for news letter"

    describe "Admin roles: a promoter" do
        it "sees the email lists and full orders" $ withContext do
            user <- createPromoter
            order <- createRoleOrder "promoter@example.com"
            forM_ [EmailsForNewsLetterAction, EmailsForDeliveryInfoAction] \action -> do
                response <- withUser user (callAction action)
                response `responseStatusShouldBe` status200
            list <- withUser user $ callAction OrdersAction
            list `responseStatusShouldBe` status200
            list `responseBodyShouldNotContain` "/admin/NewOrder"
            page <- withUser user $ callAction ShowOrderAction { orderId = order.id }
            page `responseBodyShouldContain` "promoter@example.com"
            page `responseBodyShouldContain` "Testikatu 1"
            menu <- withUser user $ callAction WelcomeAction
            menu `responseBodyShouldContain` "Emails for news letter"
            menu `responseBodyShouldContain` "Orders"
            menu `responseBodyShouldContain` "Products"
            menu `responseBodyShouldNotContain` "Customers"
            menu `responseBodyShouldNotContain` "Payment Instructions"

        it "doesn't change orders or the shop" $ withContext do
            user <- createPromoter
            order <- createRoleOrder "promoterchanges@example.com"
            page <- withUser user $ callAction ShowOrderAction { orderId = order.id }
            page `responseBodyShouldNotContain` "Mark as delivered"
            page `responseBodyShouldNotContain` "Send invoice"
            denied (withUser user $ callAction UpdateDeliverOrderAction { orderId = order.id }) `shouldReturn` True
            denied (withUser user $ callAction NewOrderAction) `shouldReturn` True
            denied (withUser user $ callAction CustomersAction) `shouldReturn` True
            order' <- fetch order.id
            order'.deliveredAt `shouldBe` Nothing

    describe "Admin roles: a promoter editing the shop's texts" do
        it "changes a product's name, description and package, nothing else" $ withContext do
            user <- createPromoter
            (producer, product) <- createTextsProduct "product"
            other <- newRecord @Producer |> set #name "Toinen tila" |> set #subject "" |> set #description "" |> createRecord
            form <- withUser user $ callAction EditProductAction { productId = product.id }
            form `responseStatusShouldBe` status200
            form `responseBodyShouldContain` "Price: 10 €"
            form `responseBodyShouldNotContain` "name=\"price\""
            form `responseBodyShouldNotContain` "Delete"
            -- A crafted request with the other fields too changes only the texts
            _ <- withUser user $ callActionWithParams UpdateProductAction { productId = product.id }
                [ ("name", "Olive oil"), ("description", "From Sicily"), ("package", "3 l can")
                , ("price", "1"), ("enabled", "off"), ("ordering", "99"), ("producerId", cs (tshow other.id))
                ]
            product' <- fetch product.id
            (product'.name, product'.description, product'.package) `shouldBe` ("Olive oil", "From Sicily", "3 l can")
            (product'.price, product'.enabled, product'.ordering, product'.producerId) `shouldBe` (1000, True, Nothing, producer.id)

        it "changes a producer's subject and description, not its name" $ withContext do
            user <- createPromoter
            (producer, _) <- createTextsProduct "producer"
            form <- withUser user $ callAction EditProducerAction { producerId = producer.id }
            form `responseBodyShouldContain` ("Name: " <> producer.name)
            _ <- withUser user $ callActionWithParams UpdateProducerAction { producerId = producer.id }
                [("name", "Renamed"), ("subject", "Olive oil from Sicily"), ("description", "A farm"), ("enabled", "off")]
            producer' <- fetch producer.id
            (producer'.name, producer'.subject, producer'.description, producer'.enabled)
                `shouldBe` (producer.name, "Olive oil from Sicily", "A farm", True)

        it "doesn't add or delete products and producers" $ withContext do
            user <- createPromoter
            (producer, product) <- createTextsProduct "catalog"
            list <- withUser user $ callAction ProductsAction
            list `responseStatusShouldBe` status200
            list `responseBodyShouldNotContain` "/admin/NewProduct"
            denied (withUser user $ callAction NewProductAction) `shouldReturn` True
            denied (withUser user $ callAction NewProducerAction) `shouldReturn` True
            denied (withUser user $ callAction DeleteProductAction { productId = product.id }) `shouldReturn` True
            denied (withUser user $ callAction DeleteProducerAction { producerId = producer.id }) `shouldReturn` True
            (query @Product |> filterWhere (#id, product.id) |> fetchCount) `shouldReturn` 1

        it "is not for a delivery person" $ withContext do
            user <- createDeliverer
            (_, product) <- createTextsProduct "deliverer"
            denied (withUser user $ callAction EditProductAction { productId = product.id }) `shouldReturn` True
            denied (withUser user $ callActionWithParams UpdateProductAction { productId = product.id } [("name", "x")]) `shouldReturn` True
            product' <- fetch product.id
            product'.name `shouldBe` product.name

    describe "Admin text history" do
        it "records who changed which product text, from what to what" $ withContext do
            user <- createPromoter
            (_, product) <- createTextsProduct "history"
            _ <- withUser user $ callActionWithParams UpdateProductAction { productId = product.id }
                [("name", cs product.name), ("description", "From Sicily"), ("package", "3 l can"), ("price", "1")]
            changes <- query @TextChange |> filterWhere (#productId, Just product.id) |> orderBy #fieldName |> fetch
            map (\c -> (c.userId, c.fieldName, c.textBefore, c.textAfter)) changes `shouldBe`
                [ (user.id, "description", "Sisiliasta", "From Sicily")
                , (user.id, "package", "3 l kanisteri", "3 l can")
                ]
            page <- withUser user $ callAction ShowProductAction { productId = product.id }
            page `responseBodyShouldContain` "admin@example.com · description</summary>"
            page `responseBodyShouldContain` "Was: Sisiliasta"
            page `responseBodyShouldContain` "Now: From Sicily"

        it "records nothing when no text changed" $ withContext do
            admin <- createUserWithRoles True False False
            (_, product) <- createTextsProduct "unchanged"
            _ <- withUser admin $ callActionWithParams UpdateProductAction { productId = product.id }
                [ ("name", cs product.name), ("description", cs product.description), ("package", cs product.package)
                , ("price", "1200"), ("producerId", cs (tshow product.producerId)), ("enabled", "on")
                ]
            (query @TextChange |> filterWhere (#productId, Just product.id) |> fetchCount) `shouldReturn` 0
            page <- withUser admin $ callAction ShowProductAction { productId = product.id }
            page `responseBodyShouldContain` "The texts haven"

        it "records an admin renaming a producer" $ withContext do
            admin <- createUserWithRoles True False False
            (producer, _) <- createTextsProduct "renamed producer"
            _ <- withUser admin $ callActionWithParams UpdateProducerAction { producerId = producer.id }
                [("name", "Uusi nimi"), ("subject", cs producer.subject), ("description", cs producer.description), ("enabled", "on")]
            changes <- query @TextChange |> filterWhere (#producerId, Just producer.id) |> fetch
            map (\c -> (c.fieldName, c.textBefore, c.textAfter)) changes `shouldBe` [("name", producer.name, "Uusi nimi")]
            page <- withUser admin $ callAction ShowProducerAction { producerId = producer.id }
            page `responseBodyShouldContain` "Now: Uusi nimi"

    describe "Admin roles: a delivery person who is also a promoter" do
        it "may do what either may" $ withContext do
            user <- createUserWithRoles False True True
            order <- createRoleOrder "both@example.com"
            emails <- withUser user $ callAction EmailsForNewsLetterAction
            emails `responseStatusShouldBe` status200
            _ <- withUser user $ callAction UpdateDeliverOrderAction { orderId = order.id }
            order' <- fetch order.id
            isJust order'.deliveredAt `shouldBe` True
            denied (withUser user $ callAction UpdateInvoiceOrderAction { orderId = order.id }) `shouldReturn` True

    describe "Admin roles: a user without a role" do
        it "can log in but sees nothing" $ withContext do
            user <- createUserWithRoles False False False
            menu <- withUser user $ callAction WelcomeAction
            menu `responseBodyShouldContain` "Your login has no role yet"
            menu `responseBodyShouldNotContain` "Orders"
            denied (withUser user $ callAction OrdersAction) `shouldReturn` True

-- | Whether the action was refused, by an exception or a 403
denied :: IO Response -> IO Bool
denied call = Exception.try @Exception.SomeException call >>= \case
    Left _ -> pure True
    Right response -> pure (responseStatus response == status403)

createRoleOrder :: (?modelContext :: ModelContext) => Text -> IO Order
createRoleOrder email = do
    customer <- newRecord @Customer
        |> set #firstName "Rooli" |> set #lastName "Asiakas"
        |> set #email email
        |> set #phone "0401234567"
        |> set #streetAddress "Testikatu 1"
        |> createRecord
    newRecord @Order |> set #customerId customer.id |> createRecord

createTextsProduct :: (?modelContext :: ModelContext) => Text -> IO (Producer, Product)
createTextsProduct tag = do
    producer <- newRecord @Producer
        |> set #name ("Tekstitila " <> tag) |> set #subject "Oliiviöljyä" |> set #description "Tila"
        |> createRecord
    product <- newRecord @Product
        |> set #producerId producer.id
        |> set #name ("Oliiviöljyä " <> tag)
        |> set #description "Sisiliasta"
        |> set #package "3 l kanisteri"
        |> set #price 1000
        |> createRecord
    pure (producer, product)
