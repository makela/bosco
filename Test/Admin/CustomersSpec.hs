module Test.Admin.CustomersSpec where

import Network.HTTP.Types (status200)

import IHP.ControllerPrelude
import IHP.Hspec (responseBodyShouldContain, responseStatusShouldBe,
                  withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.Controller.Customers ()
import Admin.FrontController ()
import Admin.Types
import Config
import Generated.Types

import Test.Admin.Users (createAdmin)

tests :: Spec
tests = aroundAll (withIHPApp AdminApplication config) do
    describe "Admin CustomersController" do
        it "sets the reverse name when an admin creates a customer" $ withContext do
            admin <- createAdmin
            _ <- withUser admin do
                callActionWithParams CreateCustomerAction (customerParams "Maija Virtanen" "maija@example.com")
            customer <- query @Customer |> filterWhere (#email, "maija@example.com") |> fetchOne
            customer.reverseName `shouldBe` "virtanen maija"

        it "lists every admin-created customer separately" $ withContext do
            admin <- createAdmin
            withUser admin do
                _ <- callActionWithParams CreateCustomerAction (customerParams "Ville Korhonen" "ville@example.com")
                _ <- callActionWithParams CreateCustomerAction (customerParams "Anna Mäkinen" "anna@example.com")
                response <- callAction CustomersAction
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ville Korhonen"
                response `responseBodyShouldContain` "Anna Mäkinen"

        it "updates the reverse name when the name is edited" $ withContext do
            admin <- createAdmin
            customer <- newRecord @Customer
                |> set #name "Old Name"
                |> set #reverseName "name old"
                |> set #email "rename@example.com"
                |> set #phone "0401234567"
                |> set #address "Testikatu 1"
                |> createRecord
            _ <- withUser admin do
                callActionWithParams UpdateCustomerAction { customerId = customer.id }
                    (customerParams "Pekka Laine" "rename@example.com")
            customer' <- fetch customer.id
            customer'.reverseName `shouldBe` "laine pekka"

        it "rejects a customer with a blank name" $ withContext do
            admin <- createAdmin
            _ <- withUser admin do
                callActionWithParams CreateCustomerAction (customerParams "   " "blank@example.com")
            count <- query @Customer |> filterWhere (#email, "blank@example.com") |> fetchCount
            count `shouldBe` 0

customerParams :: Text -> Text -> [(ByteString, ByteString)]
customerParams name email =
    [ ("name", cs name)
    , ("email", cs email)
    , ("phone", "0401234567")
    , ("address", "Testikatu 1")
    ]
