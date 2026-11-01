module Main where

import IHP.Prelude
import Test.Hspec

import qualified Test.Admin.CustomersSpec
import qualified Test.Admin.DeleteSpec
import qualified Test.Admin.OrderedProductsSpec
import qualified Test.Admin.OrdersSpec
import qualified Test.Web.CreateOrderSpec
import qualified Test.Web.OrdersSpec

main :: IO ()
main = hspec do
    Test.Web.OrdersSpec.tests
    Test.Web.CreateOrderSpec.tests
    Test.Admin.CustomersSpec.tests
    Test.Admin.OrdersSpec.tests
    Test.Admin.DeleteSpec.tests
    Test.Admin.OrderedProductsSpec.tests
