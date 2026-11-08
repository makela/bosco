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

            it "refuse unknown roles" $ withContext do
                response <- inApp (httpPost "/admin/DemoLogin?role=root" [])
                statusCode (simpleStatus response) `shouldBe` 404
  where
    usersWithEmail :: (?modelContext :: ModelContext) => Text -> IO Int
    usersWithEmail email = query @User |> filterWhere (#email, email) |> fetchCount
