module Test.Admin.CustomersSpec where

import Network.HTTP.Types (status200)

import IHP.ControllerPrelude
import IHP.Hspec (responseBodyShouldContain, responseBodyShouldNotContain,
                  responseStatusShouldBe, withIHPApp)
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
                callActionWithParams CreateCustomerAction (customerParams "Maija" "Virtanen" "maija@example.com")
            customer <- query @Customer |> filterWhere (#email, "maija@example.com") |> fetchOne
            customer.reverseName `shouldBe` "virtanen maija"

        it "lists every admin-created customer separately" $ withContext do
            admin <- createAdmin
            withUser admin do
                _ <- callActionWithParams CreateCustomerAction (customerParams "Ville" "Korhonen" "ville@example.com")
                _ <- callActionWithParams CreateCustomerAction (customerParams "Anna" "Mäkinen" "anna@example.com")
                response <- callAction CustomersAction
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ville Korhonen"
                response `responseBodyShouldContain` "Anna Mäkinen"

        it "updates the reverse name when the name is edited" $ withContext do
            admin <- createAdmin
            customer <- newRecord @Customer
                |> set #firstName "Old Name"
                |> set #reverseName "name old"
                |> set #email "rename@example.com"
                |> set #phone "0401234567"
                |> set #streetAddress "Testikatu 1"
                |> createRecord
            _ <- withUser admin do
                callActionWithParams UpdateCustomerAction { customerId = customer.id }
                    (customerParams "Pekka" "Laine" "rename@example.com")
            customer' <- fetch customer.id
            customer'.reverseName `shouldBe` "laine pekka"

        it "shows a customer's details, the name for the invoice too" $ withContext do
            admin <- createAdmin
            customer <- newRecord @Customer
                |> set #firstName "Maija" |> set #lastName "Virtanen" |> set #billingName "Oliivi Oy"
                |> set #email "details@example.com" |> set #phone "0401234567"
                |> set #streetAddress "Kotitie 12 B 4" |> set #postalCode "33100" |> set #city "Tampere"
                |> createRecord
            forM_ [ShowCustomerAction customer.id, EditCustomerAction customer.id] \action -> do
                response <- withUser admin (callAction action)
                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Maija Virtanen"
                response `responseBodyShouldContain` "Oliivi Oy"
            shown <- withUser admin (callAction (ShowCustomerAction customer.id))
            shown `responseBodyShouldContain` "<p>33100 Tampere</p>"

        it "shows the name and address as written before the split, when there are any" $ withContext do
            admin <- createAdmin
            let customer = newRecord @Customer
                    |> set #firstName "Matti" |> set #lastName "Virtanen"
                    |> set #email "original@example.com" |> set #phone "0401234567"
            migrated <- customer
                |> set #name "matti virtanen" |> set #address "Testikatu 1, 00100 Hki"
                |> createRecord
            new <- customer |> createRecord
            migratedForm <- withUser admin (callAction (EditCustomerAction migrated.id))
            migratedForm `responseBodyShouldContain` "Name: matti virtanen"
            migratedForm `responseBodyShouldContain` "Address: Testikatu 1, 00100 Hki"
            newForm <- withUser admin (callAction (EditCustomerAction new.id))
            newForm `responseBodyShouldNotContain` "original-details"

        it "keeps the name and address as written when the customer is edited" $ withContext do
            admin <- createAdmin
            customer <- newRecord @Customer
                |> set #name "matti virtanen" |> set #address "Testikatu 1, 00100 Hki"
                |> set #email "keep@example.com" |> set #phone "0401234567"
                |> createRecord
            _ <- withUser admin do
                callActionWithParams UpdateCustomerAction { customerId = customer.id }
                    (customerParams "Matti" "Virtanen" "keep@example.com")
            customer' <- fetch customer.id
            (customer'.name, customer'.address, customer'.firstName) `shouldBe` ("matti virtanen", "Testikatu 1, 00100 Hki", "Matti")

        it "rejects a customer with a blank first name" $ withContext do
            admin <- createAdmin
            _ <- withUser admin do
                callActionWithParams CreateCustomerAction (customerParams "   " "Virtanen" "blank@example.com")
            count <- query @Customer |> filterWhere (#email, "blank@example.com") |> fetchCount
            count `shouldBe` 0

        it "saves a customer without an address" $ withContext do
            admin <- createAdmin
            _ <- withUser admin do
                callActionWithParams CreateCustomerAction $
                    map (\(k, v) -> if k `elem` ["streetAddress", "postalCode", "city"] then (k, "") else (k, v))
                        (customerParams "Leena" "Salminen" "noaddress@example.com")
            count <- query @Customer |> filterWhere (#email, "noaddress@example.com") |> fetchCount
            count `shouldBe` 1

        it "rejects a malformed postal code" $ withContext do
            admin <- createAdmin
            _ <- withUser admin do
                callActionWithParams CreateCustomerAction $
                    map (\(k, v) -> if k == "postalCode" then (k, "001") else (k, v))
                        (customerParams "Leena" "Salminen" "badcode@example.com")
            count <- query @Customer |> filterWhere (#email, "badcode@example.com") |> fetchCount
            count `shouldBe` 0

customerParams :: Text -> Text -> Text -> [(ByteString, ByteString)]
customerParams firstName lastName email =
    [ ("firstName", cs firstName)
    , ("lastName", cs lastName)
    , ("email", cs email)
    , ("phone", "0401234567")
    , ("streetAddress", "Testikatu 1")
    , ("postalCode", "00100")
    , ("city", "Helsinki")
    ]
