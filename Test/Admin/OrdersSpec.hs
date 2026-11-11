module Test.Admin.OrdersSpec where

import qualified Control.Exception as Exception
import Network.HTTP.Types (hLocation, hReferer, status200)
import Network.Wai (requestHeaders, responseHeaders)

import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (..))
import IHP.Hspec (responseBodyShouldContain, responseBodyShouldNotContain,
                  responseStatusShouldBe, withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.Controller.Orders ()
import Admin.FrontController ()
import Admin.Types
import Config
import Generated.Types

import Test.Admin.Users (createAdmin, createTestUser)

tests :: Spec
tests = aroundAll (withIHPApp AdminApplication config) do
    describe "Admin OrdersController search" do
        it "finds orders by part of the customer's name" $ withContext do
            admin <- setUp
            response <- withUser admin $ search "virt"
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Maija (Mäki) Virtanen"
            response `responseBodyShouldNotContain` "Ville Korhonen"

        it "finds orders by the name for the invoice" $ withContext do
            admin <- setUp
            response <- withUser admin $ search "oliivi oy"
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Ville Korhonen"
            response `responseBodyShouldNotContain` "Maija (Mäki) Virtanen"

        it "leaves out the paid orders when asked to" $ withContext do
            admin <- setUp
            customer <- newRecord @Customer
                |> set #firstName "Paula Maksanut"
                |> set #email "paula@example.com"
                |> set #phone "0401234567"
                |> set #streetAddress "Testikatu 2"
                |> createRecord
            now <- getCurrentTime
            _ <- newRecord @Order |> set #customerId customer.id |> setJust #paidAt now |> createRecord
            everything <- withUser admin $ callActionWithParams OrdersAction []
            everything `responseBodyShouldContain` "Paula Maksanut"
            unpaid <- withUser admin $ callActionWithParams OrdersAction [("excludePaid", "on")]
            unpaid `responseBodyShouldNotContain` "Paula Maksanut"
            unpaid `responseBodyShouldContain` "Ville Korhonen"
            notInvoiced <- withUser admin $ callActionWithParams OrdersAction [("excludeInvoiced", "on")]
            notInvoiced `responseBodyShouldContain` "Paula Maksanut"

        it "treats parentheses as plain text instead of crashing" $ withContext do
            admin <- setUp
            response <- withUser admin $ search "maija ("
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Maija (Mäki) Virtanen"
            response `responseBodyShouldNotContain` "Ville Korhonen"

        it "survives other regex metacharacters" $ withContext do
            admin <- setUp
            forM_ ["(", "[", "*", "+", "\\", "a{"] \q -> do
                response <- withUser admin $ search q
                response `responseStatusShouldBe` status200

        it "works the same for non-admin users" $ withContext do
            _ <- setUp
            user <- createTestUser False
            response <- withUser user $ search "korhonen"
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Ville Korhonen"
            response `responseBodyShouldNotContain` "Maija (Mäki) Virtanen"

        it "shows the mark-as-paid button only to admins" $ withContext do
            admin <- setUp
            user <- createTestUser False
            adminView <- withUser admin $ search ""
            adminView `responseBodyShouldContain` "Mark as paid"
            userView <- withUser user $ search ""
            userView `responseBodyShouldContain` "Ville Korhonen"
            userView `responseBodyShouldNotContain` "Mark as paid"

    describe "Admin OrdersController sending the invoice again" do
        it "queues the invoice email for the order" $ withContext do
            admin <- createAdmin
            order <- createEmailOrder "send@example.com"
            _ <- withUser admin $ callAction UpdateSendInvoiceOrderAction { orderId = order.id }
            emailJobCount order `shouldReturn` 1
            -- Sending again is how the invoice is sent to a corrected address
            _ <- withUser admin $ callAction UpdateSendInvoiceOrderAction { orderId = order.id }
            emailJobCount order `shouldReturn` 2
            order' <- fetch order.id
            order'.invoicedAt `shouldBe` Nothing

        it "doesn't let a user who isn't an admin send it" $ withContext do
            user <- createTestUser False
            order <- createEmailOrder "notadmin@example.com"
            _ <- Exception.try @Exception.SomeException $
                withUser user $ callAction UpdateSendInvoiceOrderAction { orderId = order.id }
            emailJobCount order `shouldReturn` 0
            page <- withUser user $ callAction ShowOrderAction { orderId = order.id }
            page `responseBodyShouldNotContain` "Send invoice"

        it "doesn't send a cancelled order's invoice" $ withContext do
            admin <- createAdmin
            order <- createEmailOrder "cancelled@example.com"
            now <- getCurrentTime
            order |> set #cancelledAt (Just now) |> updateRecord
            _ <- withUser admin $ callAction UpdateSendInvoiceOrderAction { orderId = order.id }
            emailJobCount order `shouldReturn` 0

        it "shows when the invoice was emailed, and failures with their error" $ withContext do
            admin <- createAdmin
            order <- createEmailOrder "history@example.com"
            before <- withUser admin $ callAction ShowOrderAction { orderId = order.id }
            before `responseBodyShouldContain` "The invoice hasn't been emailed."
            forM_ [(JobStatusSucceeded, Nothing), (JobStatusFailed, Just "SMTP said no")] \(status, lastError) ->
                newRecord @EmailOrderJob
                    |> set #orderId order.id |> set #status status |> set #lastError lastError
                    |> createRecord
            page <- withUser admin $ callAction ShowOrderAction { orderId = order.id }
            page `responseStatusShouldBe` status200
            page `responseBodyShouldContain` "Send invoice"
            -- In the browser's time zone, through IHP's helpers.js
            page `responseBodyShouldContain` "Emailed <time class=\"date-time\" datetime="
            page `responseBodyShouldContain` ": SMTP said no"

    describe "Admin OrdersController marking paid" do
        it "goes back to the list as it was, filters and sorting included" $ withContext do
            admin <- createAdmin
            order <- createEmailOrder "paid@example.com"
            let list = "http://localhost:8000/admin/Orders?year=2026&ordering=price&orderDir=descending&excludePaid=on"
            response <- let ?request = ?request { requestHeaders = (hReferer, list) : requestHeaders ?request }
                in withUser admin $ callAction UpdateMarkPaidOrderAction { orderId = order.id }
            lookup hLocation (responseHeaders response) `shouldBe` Just list
            order' <- fetch order.id
            isJust order'.paidAt `shouldBe` True

    describe "Admin OrdersController prices" do
        it "lists an order at the price it was placed at" $ withContext do
            admin <- createAdmin
            producer <- newRecord @Producer |> set #name "Hintatila" |> set #subject "" |> set #description "" |> createRecord
            product <- newRecord @Product
                |> set #producerId producer.id
                |> set #name "Hintaöljy"
                |> set #description ""
                |> set #package "1 l"
                |> set #price 1500
                |> createRecord
            customer <- newRecord @Customer
                |> set #firstName "Hinta" |> set #lastName "Asiakas"
                |> set #email "price@example.com"
                |> set #phone "0401234567"
                |> set #streetAddress "Testikatu 1"
                |> createRecord
            order <- newRecord @Order |> set #customerId customer.id |> createRecord
            _ <- newRecord @OrderedProduct
                |> set #orderId order.id
                |> set #productId product.id
                |> set #quantity 2
                |> set #unitPrice 1000
                |> createRecord
            response <- withUser admin $ search "hinta asiakas"
            response `responseBodyShouldContain` "Hinta Asiakas"
            response `responseBodyShouldContain` "20\160€"
            response `responseBodyShouldNotContain` "30\160€"
  where
    search q = callActionWithParams OrdersAction [("q", q)]

-- | Two orders (created once) and a fresh admin.
setUp :: (?modelContext :: ModelContext) => IO User
setUp = do
    existing <- query @Order |> fetchCount
    when (existing == 0) do
        forM_ [("Maija (Mäki) Virtanen", ""), ("Ville Korhonen", "Oliivi Oy")] \(name, billingName) -> do
            customer <- newRecord @Customer
                |> set #firstName name
                |> set #billingName billingName
                |> set #email "test@example.com"
                |> set #phone "0401234567"
                |> set #streetAddress "Testikatu 1"
                |> createRecord
            newRecord @Order |> set #customerId customer.id |> createRecord
    createAdmin

-- | An order of a customer of its own, so its email jobs are its own
createEmailOrder :: (?modelContext :: ModelContext) => Text -> IO Order
createEmailOrder email = do
    customer <- newRecord @Customer
        |> set #firstName "Laskun" |> set #lastName "Saaja"
        |> set #email email
        |> set #phone "0401234567"
        |> createRecord
    newRecord @Order |> set #customerId customer.id |> createRecord

emailJobCount :: (?modelContext :: ModelContext) => Order -> IO Int
emailJobCount order = query @EmailOrderJob |> filterWhere (#orderId, order.id) |> fetchCount
