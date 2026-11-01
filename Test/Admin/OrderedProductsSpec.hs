module Test.Admin.OrderedProductsSpec where

import Network.HTTP.Types (status200)

import IHP.ControllerPrelude
import IHP.Hspec (responseBodyShouldContain, responseStatusShouldBe,
                  withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.Controller.Orders ()
import Admin.FrontController ()
import Admin.Types
import Config
import Generated.Types

import Test.Admin.Users (createAdmin)

tests :: Spec
tests = aroundAll (withIHPApp AdminApplication config) do
    describe "Admin OrderedProductsAction" do
        -- Runs first, while this test database has no orders at all
        it "shows the page before anything has been ordered" $ withContext do
            admin <- createAdmin
            response <- withUser admin $ callAction OrderedProductsAction
            response `responseStatusShouldBe` status200

        it "counts ordered quantities per product" $ withContext do
            admin <- createAdmin
            producer <- newRecord @Producer |> set #name "Laskutila" |> set #subject "" |> set #description "" |> createRecord
            product <- newRecord @Product
                |> set #producerId producer.id
                |> set #name "Laskuöljy"
                |> set #description ""
                |> set #package "1 l"
                |> set #price 1000
                |> createRecord
            customer <- newRecord @Customer
                |> set #name "Laskija"
                |> set #email "count@example.com"
                |> set #phone "0401234567"
                |> set #address "Testikatu 1"
                |> createRecord
            forM_ [2, 3] \quantity -> do
                order <- newRecord @Order |> set #customerId customer.id |> createRecord
                newRecord @OrderedProduct
                    |> set #orderId order.id
                    |> set #productId product.id
                    |> set #quantity quantity
                    |> set #unitPrice 1000
                    |> createRecord
            response <- withUser admin $ callAction OrderedProductsAction
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Laskuöljy (1 l)"
            response `responseBodyShouldContain` "<td>5</td>"
