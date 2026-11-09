module Test.Admin.DeleteSpec where

import Network.HTTP.Types (statusCode)
import Network.Wai.Test (SResponse (..), Session)

import IHP.ControllerPrelude
import IHP.Hspec (withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.Types
import Config
import Generated.Types

import Test.App

tests :: Spec
tests = aroundAll (withIHPApp AdminApplication config) do
    describe "Admin deletes" do
        it "refuses to delete a product that has been ordered" $ withContext do
            (_, product, _) <- createTestOrderedProduct "ordered product"
            page <- asAdmin $ httpDelete ("/admin/DeleteProduct?productId=" <> idToParam product.id) >>= followRedirect
            bodyText page `shouldSatisfy` ("cannot be deleted because it has been ordered" `isInfixOf`)
            fetchOneOrNothing product.id >>= (`shouldSatisfy` isJust)

        it "deletes a product that has not been ordered" $ withContext do
            producer <- createTestProducer "unordered product"
            product <- createTestProduct producer "Unordered"
            page <- asAdmin $ httpDelete ("/admin/DeleteProduct?productId=" <> idToParam product.id) >>= followRedirect
            bodyText page `shouldSatisfy` ("Product deleted" `isInfixOf`)
            fetchOneOrNothing product.id >>= (`shouldSatisfy` isNothing)

        it "refuses to delete a producer that has products" $ withContext do
            producer <- createTestProducer "with products"
            _ <- createTestProduct producer "Kept"
            page <- asAdmin $ httpDelete ("/admin/DeleteProducer?producerId=" <> idToParam producer.id) >>= followRedirect
            bodyText page `shouldSatisfy` ("cannot be deleted because it has products" `isInfixOf`)
            fetchOneOrNothing producer.id >>= (`shouldSatisfy` isJust)

        it "deletes a producer without products" $ withContext do
            producer <- createTestProducer "without products"
            page <- asAdmin $ httpDelete ("/admin/DeleteProducer?producerId=" <> idToParam producer.id) >>= followRedirect
            bodyText page `shouldSatisfy` ("Producer deleted" `isInfixOf`)
            fetchOneOrNothing producer.id >>= (`shouldSatisfy` isNothing)

        it "refuses to delete a customer who has orders" $ withContext do
            (customer, _, _) <- createTestOrderedProduct "customer with orders"
            page <- asAdmin $ httpDelete ("/admin/DeleteCustomer?customerId=" <> idToParam customer.id) >>= followRedirect
            bodyText page `shouldSatisfy` ("cannot be deleted because they have orders" `isInfixOf`)
            fetchOneOrNothing customer.id >>= (`shouldSatisfy` isJust)

        it "deletes a customer without orders" $ withContext do
            customer <- createTestCustomer "No Orders"
            page <- asAdmin $ httpDelete ("/admin/DeleteCustomer?customerId=" <> idToParam customer.id) >>= followRedirect
            bodyText page `shouldSatisfy` ("Customer deleted" `isInfixOf`)
            fetchOneOrNothing customer.id >>= (`shouldSatisfy` isNothing)

-- | Logs in as an admin (created on first use), then runs the requests.
asAdmin :: (?modelContext :: ModelContext, ?mocking :: MockContext AdminApplication) => Session a -> IO a
asAdmin requests = do
    let email = "login-admin@example.com"
        password = "a long test password"
    existing <- query @User |> filterWhere (#email, email) |> fetchCount
    when (existing == 0) do
        passwordHash <- hashPassword password
        _ <- newRecord @User
            |> set #email email
            |> set #passwordHash passwordHash
            |> set #isAdmin True
            |> createRecord
        pure ()
    inApp do
        loggedIn <- logIn email password
        -- A failed login re-renders the form instead of redirecting
        when (statusCode (simpleStatus loggedIn) `div` 100 /= 3) (error "Logging in failed")
        requests

createTestProducer :: (?modelContext :: ModelContext) => Text -> IO Producer
createTestProducer name = newRecord @Producer
    |> set #name name
    |> set #subject ""
    |> set #description ""
    |> createRecord

createTestProduct :: (?modelContext :: ModelContext) => Producer -> Text -> IO Product
createTestProduct producer name = newRecord @Product
    |> set #producerId producer.id
    |> set #name name
    |> set #description ""
    |> set #package "1 l"
    |> set #price 1000
    |> createRecord

createTestCustomer :: (?modelContext :: ModelContext) => Text -> IO Customer
createTestCustomer name = newRecord @Customer
    |> set #firstName name
    |> set #email "customer@example.com"
    |> set #phone "0401234567"
    |> set #streetAddress "Testikatu 1"
    |> createRecord

-- | A customer with one order for one product of a new producer.
createTestOrderedProduct :: (?modelContext :: ModelContext) => Text -> IO (Customer, Product, Order)
createTestOrderedProduct tag = do
    producer <- createTestProducer tag
    product <- createTestProduct producer "Ordered"
    customer <- createTestCustomer "Has Orders"
    order <- newRecord @Order |> set #customerId customer.id |> createRecord
    _ <- newRecord @OrderedProduct
        |> set #orderId order.id
        |> set #productId product.id
        |> set #quantity 1
        |> createRecord
    pure (customer, product, order)
