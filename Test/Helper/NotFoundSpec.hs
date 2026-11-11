module Test.Helper.NotFoundSpec where

import Network.HTTP.Types (Status, hContentType, status200, status404)
import Network.Wai (Application, responseLBS)
import Network.Wai.Test (SResponse (..), defaultRequest, request, runSession, setPath)
import IHP.HSX.Markup (renderMarkupText)

import IHP.Environment (Environment (..))
import IHP.ModelSupport (RecordNotFoundException (..))
import IHP.Prelude
import Test.Hspec

import Application.Localization
import Application.NotFound

-- | An app that answers every request with the given status and content type
answering :: Status -> ByteString -> Application
answering status contentType _ respond =
    respond (responseLBS status [(hContentType, contentType)] "the app's own page")

getPath :: ByteString -> Application -> IO SResponse
getPath path app = runSession (request (setPath defaultRequest path)) app

body :: SResponse -> Text
body = cs . simpleBody

tests :: Spec
tests = describe "Application.NotFound" do
    it "replaces a page not found with one in the site's language" do
        response <- getPath "/no-such-page" (localizedNotFound Development (answering status404 "text/html"))
        simpleStatus response `shouldBe` status404
        body response `shouldSatisfy` ("<html lang=\"fi\">" `isInfixOf`)
        body response `shouldSatisfy` ("Sivua ei löytynyt" `isInfixOf`)

    it "has the admin's pages not found in English, like the admin" do
        response <- getPath "/admin/NoSuchPage" (localizedNotFound Development (answering status404 "text/html; charset=utf-8"))
        body response `shouldSatisfy` ("<html lang=\"en\">" `isInfixOf`)
        body response `shouldSatisfy` ("Page not found" `isInfixOf`)

    it "leaves other pages alone" do
        found <- getPath "/" (localizedNotFound Development (answering status200 "text/html"))
        body found `shouldBe` "the app's own page"
        notHtml <- getPath "/no-such-page" (localizedNotFound Development (answering status404 "application/json"))
        body notHtml `shouldBe` "the app's own page"

    it "has a missing record not found in production" do
        let missing :: Application
            missing _ _ = throwIO RecordNotFoundException { queryAndParams = "SELECT * FROM orders WHERE id = ?" }
        response <- getPath "/ShowOrder" (localizedNotFound Production missing)
        simpleStatus response `shouldBe` status404
        body response `shouldSatisfy` ("Sivua ei löytynyt" `isInfixOf`)
        -- IHP's error page tells the developer what was missing
        getPath "/ShowOrder" (localizedNotFound Development missing) `shouldThrow` \(_ :: RecordNotFoundException) -> True

    it "has a page in every language" do
        forM_ [minBound .. maxBound] \locale -> do
            let page = renderMarkupText (notFoundPage locale)
            page `shouldSatisfy` (("<html lang=\"" <> localeCode locale <> "\">") `isInfixOf`)
            page `shouldSatisfy` ("img { display: block; max-width: 100%" `isInfixOf`)
            -- The title, as the text's apostrophe is escaped in HTML
            page `shouldSatisfy` (l10nText' LPageNotFoundTitle locale `isInfixOf`)
