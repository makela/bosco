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
            menu `responseBodyShouldNotContain` "Producers"

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
