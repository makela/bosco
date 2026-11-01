module Test.Helper.ControllerSpec where

import IHP.Prelude
import Test.Hspec

import Application.Helper.Controller

tests :: Spec
tests = describe "Application.Helper.Controller" do
    describe "reverseNameOf" do
        it "reverses the words and lower-cases them" do
            reverseNameOf "Maija Virtanen" `shouldBe` "virtanen maija"

        it "handles more than two names" do
            reverseNameOf "Anna Maria Korhonen" `shouldBe` "korhonen maria anna"

        it "collapses extra whitespace" do
            reverseNameOf "  Maija   Virtanen " `shouldBe` "virtanen maija"

        it "is empty only for a blank name" do
            reverseNameOf "   " `shouldBe` ""

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
