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
  where
    search q = callActionWithParams OrdersAction [("q", q)]

-- | Two orders (created once) and a fresh admin.
setUp :: (?modelContext :: ModelContext) => IO User
setUp = do
    existing <- query @Order |> fetchCount
    when (existing == 0) do
        forM_ ["Maija (Mäki) Virtanen", "Ville Korhonen"] \name -> do
            customer <- newRecord @Customer
                |> set #name name
                |> set #email "test@example.com"
                |> set #phone "0401234567"
                |> set #address "Testikatu 1"
                |> createRecord
            newRecord @Order |> set #customerId customer.id |> createRecord
    createAdmin
