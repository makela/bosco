module Test.Helper.SettingsSpec where

import Data.Either (isLeft)

import IHP.Prelude
import Test.Hspec

import Application.Localization (Locale (..), parseLocale)

tests :: Spec
tests = describe "Instance settings" do
    describe "parseLocale (APP_LOCALE)" do
        it "reads the language codes" do
            map parseLocale ["fi", "en", "fr"] `shouldBe` [Right FI, Right EN, Right FR]

        it "uses Finnish when unset" do
            parseLocale "" `shouldBe` Right FI

        it "rejects other values and lists the valid ones" do
            parseLocale "FR" `shouldBe` Left "APP_LOCALE should be one of fi, en, fr, got FR"
            parseLocale "sv" `shouldSatisfy` isLeft

