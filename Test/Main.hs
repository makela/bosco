module Main where

import IHP.Prelude
import Test.Hspec

import qualified Test.Helper.ControllerSpec
import qualified Test.Web.SortingSpec

main :: IO ()
main = hspec do
    Test.Helper.ControllerSpec.tests
    Test.Web.SortingSpec.tests
