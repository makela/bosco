module Test.Helper.CustomerSpec where

import IHP.Prelude
import IHP.ModelSupport (newRecord)
import Test.Hspec

import Application.Customer
import Generated.Types

tests :: Spec
tests = describe "Application.Customer" do
    describe "reverseNameOf" do
        it "puts the last name first and lower-cases" do
            reverseNameOf "Maija" "Virtanen" `shouldBe` "virtanen maija"

        it "keeps the first names in order" do
            reverseNameOf "Anna Maria" "Korhonen" `shouldBe` "korhonen anna maria"

        it "collapses extra whitespace" do
            reverseNameOf "  Maija " "  Virtanen" `shouldBe` "virtanen maija"

        it "is just the first name without a last name" do
            reverseNameOf "Cher" "" `shouldBe` "cher"

    describe "fullName" do
        it "is the first and last name" do
            fullName (customer "Anna-Liisa" "Mäki") `shouldBe` "Anna-Liisa Mäki"

        it "is just the first name without a last name" do
            fullName (customer "Cher" "") `shouldBe` "Cher"

    describe "nameLines" do
        it "is the name for the invoice, then the customer's name" do
            nameLines ((customer "Maija" "Virtanen") { billingName = "Oliivi Oy" }) `shouldBe` ["Oliivi Oy", "Maija Virtanen"]

        it "is just the customer's name without a name for the invoice" do
            nameLines ((customer "Maija" "Virtanen") { billingName = "  " }) `shouldBe` ["Maija Virtanen"]

    describe "addressLines" do
        it "puts the street on one line and postal code and city on the next" do
            addressLines (address "Kotitie 12 B 4" "33100" "Tampere") `shouldBe` ["Kotitie 12 B 4", "33100 Tampere"]

        it "leaves out what is missing" do
            addressLines (address "Kotitie 12" "" "") `shouldBe` ["Kotitie 12"]
            addressLines (address "Kotitie 12" "" "Nummela") `shouldBe` ["Kotitie 12", "Nummela"]
            addressLines (address "" "" "") `shouldBe` []
  where
    customer firstName lastName = (newRecord @Customer) { firstName, lastName }
    address streetAddress postalCode city = (newRecord @Customer) { streetAddress, postalCode, city }
