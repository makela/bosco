module Test.Helper.CreateUserSpec where

import IHP.Prelude
import Data.Either (isLeft)
import Test.Hspec

-- Importing the script also keeps it compiling: nothing else builds it
import Application.Script.CreateUser (parseRoles)

tests :: Spec
tests = describe "Application.Script.CreateUser.parseRoles" do
    it "reads one role" do
        parseRoles "promoter" `shouldBe` Right ["promoter"]

    it "reads several, ignoring case, spaces and repeats" do
        parseRoles " Deliverer, promoter,deliverer " `shouldBe` Right ["deliverer", "promoter"]

    it "refuses no roles" do
        parseRoles " , " `shouldSatisfy` isLeft

    it "refuses an unknown role" do
        parseRoles "admin,translator" `shouldBe` Left "Unknown roles translator, known: admin, deliverer, promoter"
