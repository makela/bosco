module Test.Web.NotFoundSpec where

import Network.HTTP.Types (status404)
import Network.Wai.Test (SResponse (..))

import IHP.ControllerPrelude
import IHP.Hspec (withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Config
import Web.Types

import Test.App

-- | The app's config has the localized pages not found, see
-- Application.NotFound. A missing record is a 404 only in production, so
-- that is tested there, in Test.Helper.NotFoundSpec.
tests :: Spec
tests = aroundAll (withIHPApp WebApplication config) do
    describe "Pages not found" do
        it "are in the site's language" $ withContext do
            response <- inApp (httpGet "/no-such-page")
            simpleStatus response `shouldBe` status404
            bodyText response `shouldSatisfy` ("Sivua ei löytynyt" `isInfixOf`)
