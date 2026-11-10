module Test.Helper.CreateUserSpec where

import IHP.Prelude
import Data.Either (isLeft)
import Test.Hspec

-- Importing the scripts also keeps them compiling: nothing else builds them
import Application.Script.CreateUser (parseRoles)
import Application.Script.SeedDevData (emailFor)

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

    it "makes the dev seed's emails without accents" do
        emailFor "Kaisa-Maria Järvinen" `shouldBe` "kaisamaria.jarvinen@example.com"
