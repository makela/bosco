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

