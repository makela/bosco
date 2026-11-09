module Test.Helper.PermissionSpec where

import IHP.Prelude
import IHP.ModelSupport (newRecord)
import Test.Hspec

import Application.Permission
import Generated.Types

tests :: Spec
tests = describe "Application.Permission" do
    let user isAdmin isDeliverer isPromoter = (newRecord @User) { isAdmin, isDeliverer, isPromoter }
        allowed u = filter (can u) [minBound .. maxBound]

    it "lets an admin do everything" do
        allowed (user True False False) `shouldBe` [minBound .. maxBound]

    it "lets a deliverer see and take orders and mark them delivered, nothing more" do
        allowed (user False True False) `shouldBe` [SeeOrders, CreateOrders, MarkDelivered]

    it "lets a promoter see orders and the email lists" do
        allowed (user False False True) `shouldBe` [SeeOrders, SeeEmailLists]

    it "lets a deliverer who is a promoter do what either may" do
        allowed (user False True True) `shouldBe` [SeeOrders, CreateOrders, MarkDelivered, SeeEmailLists]

    it "lets a user without a role do nothing" do
        allowed (user False False False) `shouldBe` []
        hasAnyRole (user False False False) `shouldBe` False

    it "keeps marking invoiced and paid, and the shop, to admins" do
        forM_ [user False True True] \u -> do
            can u ManageOrders `shouldBe` False
            can u ManageShop `shouldBe` False
