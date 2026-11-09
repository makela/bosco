module Test.Helper.ControllerSpec where

import IHP.Prelude
import Test.Hspec

import IHP.ValidationSupport (ValidatorResult (..))

import Application.Helper.Controller

tests :: Spec
tests = describe "Application.Helper.Controller" do
    describe "isPostalCode" do
        it "accepts five digits, spaces around them too" do
            isPostalCode "00100" `shouldBe` Success
            isPostalCode " 33100 " `shouldBe` Success

        it "rejects anything else" do
            forM_ ["", "0010", "001000", "00 100", "FI-00100", "00100 Helsinki"] \code ->
                isPostalCode code `shouldNotBe` Success

    describe "matchesSearch" do
        it "matches everything when the query is empty" do
            matchesSearch "" "Maija Virtanen" `shouldBe` True

        it "matches everything when the query is only whitespace" do
            matchesSearch "  " "Maija Virtanen" `shouldBe` True

        it "matches a substring case-insensitively" do
            matchesSearch "VIRT" "Maija Virtanen" `shouldBe` True

        it "matches non-ASCII letters case-insensitively" do
            matchesSearch "mäki" "Ville Mäkinen" `shouldBe` True

        it "does not match unrelated names" do
            matchesSearch "korhonen" "Maija Virtanen" `shouldBe` False

        it "ignores surrounding whitespace in the query" do
            matchesSearch " maija " "Maija Virtanen" `shouldBe` True

        -- These used to be compiled as regexes and crashed the order list.
        it "treats regex metacharacters as plain text" do
            matchesSearch "maija (" "Maija (Mäki) Virtanen" `shouldBe` True
            matchesSearch "(" "Maija Virtanen" `shouldBe` False
            matchesSearch "[" "Maija Virtanen" `shouldBe` False
            matchesSearch "*" "Maija Virtanen" `shouldBe` False
            matchesSearch "m.ija" "Maija Virtanen" `shouldBe` False

    describe "isPhone" do
        let accepts phone = it ("accepts " <> cs (show phone)) (isValid (isPhone phone) `shouldBe` True)
            rejects phone = it ("rejects " <> cs (show phone)) (isValid (isPhone phone) `shouldBe` False)
            isValid = \case
                Success -> True
                _ -> False
        accepts "0401234567"
        accepts "040 123 4567"
        accepts "040-1234567"
        accepts "040-123 4567"
        accepts "09 1234567"
        accepts "+358 40 123 4567"
        accepts "+358-40-123-4567"
        accepts "358401234567"
        rejects ""
        rejects "0"
        accepts "09 12345"
        rejects "040123"
        rejects "040 123 456 789 0"
        rejects "+35840"
        rejects "4012345678"
        rejects "+++++++++++"
        rejects "0+0+0+0+0"
        rejects "040+1234567"
        rejects "-0401234567"
        rejects "------------"
        rejects "040 abc 4567"
        -- Other countries' numbers, with the country code
        accepts "+39 333 123 4567"      -- Italian mobile
        accepts "+39 06 1234 5678"      -- Rome
        accepts "+33 6 12 34 56 78"     -- French mobile
        accepts "+1 555-123-4567"       -- North America
        accepts "+49 30 1234567"        -- Berlin
        accepts "+683 4002"             -- Niue, 7 digits
        accepts "+86 138 0013 8000 1"   -- 14 digits
        accepts "0039 333 123 4567"
        accepts "00358 40 123 4567"
        rejects "+39 333"
        rejects "+39 333 123 4567 89012" -- 16 digits
        rejects "+039 333 123 4567"
        rejects "000 123 4567"
        rejects "00"
        rejects "+"
