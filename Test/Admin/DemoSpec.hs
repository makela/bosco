module Test.Admin.DemoSpec where

import qualified Data.Text as T
import Network.HTTP.Types (statusCode)
import Network.Wai.Test (SResponse (..))

import IHP.ControllerPrelude
import IHP.Hspec (withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.Types
import Application.Settings (DemoMode (..))
import Config
import Generated.Types

import Test.App

tests :: Spec
tests = do
    aroundAll (withIHPApp AdminApplication config) do
        describe "Admin demo logins on an instance that isn't a demo" do
            it "are not offered on the login page" $ withContext do
                page <- inApp (httpGet "/admin/NewSession")
                bodyText page `shouldSatisfy` (not . ("Try the admin" `T.isInfixOf`))

            it "can't be used" $ withContext do
                response <- inApp (httpPost "/admin/DemoLogin?role=admin" [])
                statusCode (simpleStatus response) `shouldBe` 404
                usersWithEmail "admin@demo.invalid" >>= (`shouldBe` 0)

    -- The first option set wins, so this one overrides APP_DEMO
    aroundAll (withIHPApp AdminApplication (option (DemoMode True) >> config)) do
        describe "Admin demo logins on a demo" do
            it "are offered on the login page" $ withContext do
                page <- inApp (httpGet "/admin/NewSession")
                bodyText page `shouldSatisfy` (">Admin</button>" `T.isInfixOf`)
                bodyText page `shouldSatisfy` (">Delivery person</button>" `T.isInfixOf`)

            it "unlock a demo user someone locked by trying passwords" $ withContext do
                locked <- newRecord @User
                    |> set #email "orders@demo.invalid"
                    |> set #passwordHash "not-a-real-hash"
                    |> set #lockedAt (Just (UTCTime (fromGregorian 2026 1 1) 0))
                    |> set #failedLoginAttempts 10
                    |> createRecord
                page <- inApp (httpPost "/admin/DemoLogin?role=orders" [] >>= followRedirect)
                bodyText page `shouldSatisfy` ("Orders" `T.isInfixOf`)
                bodyText page `shouldSatisfy` (not . ("Producers" `T.isInfixOf`))
                user <- fetch locked.id
                (user.lockedAt, user.failedLoginAttempts, user.isAdmin) `shouldBe` (Nothing, 0, False)

            it "log in as an admin with one click, reusing the same user" $ withContext do
                page <- inApp (httpPost "/admin/DemoLogin?role=admin" [] >>= followRedirect)
                bodyText page `shouldSatisfy` ("Producers" `T.isInfixOf`)
                bodyText page `shouldSatisfy` (not . ("Change password" `T.isInfixOf`))
                _ <- inApp (httpPost "/admin/DemoLogin?role=admin" [])
                usersWithEmail "admin@demo.invalid" >>= (`shouldBe` 1)

            it "can't change their password" $ withContext do
                page <- inApp do
                    _ <- httpPost "/admin/DemoLogin?role=admin" []
                    httpPost "/admin/UpdatePassword"
                        [ ("oldPassword", "")
                        , ("newPassword", "a new long password")
                        , ("confirmPassword", "a new long password")
                        ] >>= followRedirect
                bodyText page `shouldSatisfy` ("passwords can" `T.isInfixOf`)
                user <- query @User |> filterWhere (#email, "admin@demo.invalid") |> fetchOne
                verifyPassword user ("a new long password" :: Text) `shouldBe` False

            it "can't change the payment details" $ withContext do
                stored <- query @PaymentInstruction |> fetchCount
                page <- inApp do
                    _ <- httpPost "/admin/DemoLogin?role=admin" []
                    httpPost "/admin/CreatePaymentInstruction" [("text", "IBAN FI12 3456 7890 1234 56")] >>= followRedirect
                bodyText page `shouldSatisfy` ("payment details are fixed" `T.isInfixOf`)
                query @PaymentInstruction |> fetchCount >>= (`shouldBe` stored)

            it "show only the fake payment details on invoices, whatever is stored" $ withContext do
                _ <- newRecord @PaymentInstruction |> set #text "IBAN FI12 3456 7890 1234 56" |> createRecord
                customer <- newRecord @Customer
                    |> set #name "Demo Customer" |> set #email "demo@example.com" |> set #phone "040 123 4567"
                    |> createRecord
                order <- newRecord @Order |> set #customerId customer.id |> createRecord
                invoice <- inApp (httpGet ("/ShowOrder?orderId=" <> idToParam order.id))
                bodyText invoice `shouldSatisfy` ("FI00 0000 0000 0000 00" `T.isInfixOf`)
                bodyText invoice `shouldSatisfy` (not . ("FI12 3456" `T.isInfixOf`))

            it "can't change the welcome message's text, only open and close ordering" $ withContext do
                message <- newRecord @WelcomeMessage
                    |> set #text "Tervetuloa tilaamaan!"
                    |> set #isOrderingEnabled True
                    |> createRecord
                count <- query @WelcomeMessage |> fetchCount
                (created, _) <- inApp do
                    _ <- httpPost "/admin/DemoLogin?role=admin" []
                    created <- httpPost "/admin/CreateWelcomeMessage" [("text", "Pay to IBAN FI12 3456"), ("isOrderingEnabled", "on")] >>= followRedirect
                    updated <- httpPost ("/admin/UpdateWelcomeMessage?welcomeMessageId=" <> idToParam message.id)
                        [("text", "Pay to IBAN FI12 3456"), ("isOrderingEnabled", "off")]
                    pure (created, updated)
                bodyText created `shouldSatisfy` ("welcome message is fixed" `T.isInfixOf`)
                query @WelcomeMessage |> fetchCount >>= (`shouldBe` count)
                updated <- fetch message.id
                (updated.text, updated.isOrderingEnabled) `shouldBe` ("Tervetuloa tilaamaan!", False)

            it "refuse unknown roles" $ withContext do
                response <- inApp (httpPost "/admin/DemoLogin?role=root" [])
                statusCode (simpleStatus response) `shouldBe` 404
  where
    usersWithEmail :: (?modelContext :: ModelContext) => Text -> IO Int
    usersWithEmail email = query @User |> filterWhere (#email, email) |> fetchCount
