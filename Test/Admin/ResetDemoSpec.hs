module Test.Admin.ResetDemoSpec where

import qualified Data.ByteString as ByteString
import qualified Data.Text.Encoding as TE

import IHP.ControllerPrelude
import IHP.Hspec (withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.FrontController ()
import Admin.Types
import Application.DemoData (resetDemoData)
import Config
import Generated.Types

tests :: Spec
tests = aroundAll (withIHPApp AdminApplication config) do
    describe "resetDemoData" do
        it "replaces everything but the logins with the catalog and made-up orders, again and again" $ withContext do
            fixtures <- TE.decodeUtf8 <$> ByteString.readFile "Application/Fixtures.sql"
            user <- newRecord @User
                |> set #email "kept@example.com"
                |> set #passwordHash "not-a-real-hash"
                |> createRecord
            -- Something a demo visitor made, which the reset removes
            _ <- newRecord @Producer |> set #name "Vandal" |> set #subject "" |> set #description "" |> createRecord
            now <- getCurrentTime
            first <- resetDemoData fixtures 1 now
            second <- resetDemoData fixtures 2 now
            orders <- query @Order |> fetchCount
            (first > 50, orders) `shouldBe` (True, second)
            query @Producer |> fetchCount >>= (`shouldBe` 6)
            query @Product |> fetchCount >>= (`shouldBe` 17)
            query @Producer |> filterWhere (#name, "Vandal") |> fetchCount >>= (`shouldBe` 0)
            query @WelcomeMessage |> fetchCount >>= (`shouldBe` 1)
            instructions <- query @PaymentInstruction |> fetch
            map (.text) instructions `shouldSatisfy` all ("FI00 0000 0000 0000 00" `isInfixOf`)
            length instructions `shouldBe` 1
            fetchOneOrNothing user.id >>= (`shouldSatisfy` isJust)
            -- Orders keep older, lower prices
            lines <- query @OrderedProduct |> fetch
            products <- query @Product |> fetch
            let priceOf productId = maybe 0 (.price) (find (\p -> p.id == productId) products)
            any (\line -> line.unitPrice < priceOf line.productId) lines `shouldBe` True
