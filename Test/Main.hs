module Main where

import IHP.Prelude
import Test.Hspec

import qualified Test.Helper.ControllerSpec
import qualified Test.Helper.DemoDataSpec
import qualified Test.Helper.LocalizationSpec
import qualified Test.Helper.SettingsSpec
import qualified Test.Web.SortingSpec

main :: IO ()
main = hspec do
    Test.Helper.ControllerSpec.tests
    Test.Helper.DemoDataSpec.tests
    Test.Helper.LocalizationSpec.tests
    Test.Helper.SettingsSpec.tests
    Test.Web.SortingSpec.tests
