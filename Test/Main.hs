module Main where

import IHP.Prelude
import Test.Hspec

import qualified Test.Helper.ControllerSpec

main :: IO ()
main = hspec do
    Test.Helper.ControllerSpec.tests
