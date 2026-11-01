module Main where

import IHP.Prelude
import Test.Hspec

import qualified Test.Web.OrdersSpec

main :: IO ()
main = hspec do
    Test.Web.OrdersSpec.tests
