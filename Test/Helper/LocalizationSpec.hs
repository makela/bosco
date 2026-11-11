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

    -- Catches a text pasted untranslated. English and French may share
    -- words like "Total", so those two aren't compared with each other.
    forM_ [EN, FR] \locale -> do
        it ("has " <> cs (show locale) <> " texts that are not copies of the Finnish ones") do
            forM_ keys \key ->
                (key, l10nText' key locale == l10nText' key FI) `shouldBe` (key, False)

        it ("has no Finnish letters in the " <> cs (show locale) <> " texts") do
            forM_ keys \key ->
                (key, T.any (`elem` ("äöåÄÖÅ" :: String)) (l10nText' key locale)) `shouldBe` (key, False)

    it "has French texts that use French typography before a colon" do
        forM_ keys \key -> do
            let text = l10nText' key FR
            (key, ":" `T.isInfixOf` text && not ("\160:" `T.isInfixOf` text)) `shouldBe` (key, False)

    it "uses Finnish by default" do
        l10nText LInvoice `shouldBe` "Lasku"
        localeCode defaultLocale `shouldBe` "fi"

    describe "formatMoney'" do
        it "writes Finnish and French amounts with a comma and the euro after" do
            forM_ [FI, FR] \locale -> do
                formatMoney' locale (1010 :: Int) `shouldBe` "10,10\160€"
                formatMoney' locale (5 :: Int) `shouldBe` "0,05\160€"
                formatMoney' locale (100050 :: Int) `shouldBe` "1000,50\160€"

        it "writes English amounts with a point and the euro before" do
            formatMoney' EN (1010 :: Int) `shouldBe` "€10.10"
            formatMoney' EN (5 :: Int) `shouldBe` "€0.05"
            formatMoney' EN (100050 :: Int) `shouldBe` "€1000.50"

        it "leaves out the cents of whole euros" do
            formatMoney' FI (5100 :: Int) `shouldBe` "51\160€"
            formatMoney' FI (10000 :: Int) `shouldBe` "100\160€"
            formatMoney' EN (5100 :: Int) `shouldBe` "€51"

        it "shows a negative amount with a minus" do
            formatMoney' FI (-1010 :: Int) `shouldBe` "-10,10\160€"
            formatMoney' EN (-1010 :: Int) `shouldBe` "-€10.10"
