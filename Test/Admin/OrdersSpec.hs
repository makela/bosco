module Test.Admin.OrdersSpec where

import Network.HTTP.Types (status200)

import IHP.ControllerPrelude
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
            response `responseBodyShouldContain` "20 €"
            response `responseBodyShouldNotContain` "30 €"
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
