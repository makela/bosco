module Test.Helper.LocalizationSpec where

import qualified Data.Text as T

import IHP.Prelude
import Test.Hspec

import Application.Localization

tests :: Spec
tests = describe "Application.Localization" do
    let keys = [minBound .. maxBound] :: [Localizable]
        locales = [minBound .. maxBound] :: [Locale]

    it "has a text for every key in every locale" do
        forM_ locales \locale -> forM_ keys \key ->
            (key, locale, T.null (T.strip (l10nText' key locale))) `shouldBe` (key, locale, False)

    it "has English texts that are not copies of the Finnish ones" do
        forM_ keys \key ->
            (key, l10nText' key EN == l10nText' key FI) `shouldBe` (key, False)

    it "has no Finnish letters in the English texts" do
        forM_ keys \key ->
            (key, T.any (`elem` ("äöåÄÖÅ" :: String)) (l10nText' key EN)) `shouldBe` (key, False)

    it "uses Finnish by default" do
        l10nText LInvoice `shouldBe` "Lasku"
        localeCode defaultLocale `shouldBe` "fi"
