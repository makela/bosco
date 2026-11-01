-- | Runs requests through the whole app (router, sessions, flash messages),
-- the way a browser would. Use these when a test needs more than one
-- controller action, e.g. to follow a redirect or stay logged in.
module Test.App
    ( inApp
    , httpGet
    , httpPost
    , httpDelete
    , followRedirect
    , logIn
    , bodyText
    ) where

import qualified Data.Text as T
import Network.HTTP.Types (hContentType, methodDelete, methodPost)
import Network.HTTP.Types.URI (renderSimpleQuery)
import Network.Wai (defaultRequest, requestHeaders, requestMethod)
import Network.Wai.Test (SRequest (..), SResponse (..), Session, runSession,
                         setPath, srequest)

import IHP.FrameworkConfig (RootApplication (..))
import IHP.Prelude
import IHP.RouterSupport (FrontController (..), mountFrontController)
import IHP.Test.Mocking

import Admin.FrontController ()
import Admin.Types (AdminApplication (..))
import Web.FrontController ()
import Web.Types (WebApplication (..))

-- Same mounts as Main.hs. Main can't be imported from a test (both are
-- module Main), so the root application is rebuilt here.
instance FrontController RootApplication where
    controllers =
        [ mountFrontController WebApplication
        , mountFrontController AdminApplication
        ]

-- | Runs the requests in one session, so cookies carry over between them.
inApp :: (?mocking :: MockContext application) => Session a -> IO a
inApp session = do
    app <- initTestApplication ?mocking
    runSession session app

httpGet :: ByteString -> Session SResponse
httpGet path = srequest (SRequest (setPath defaultRequest path) "")

httpPost :: ByteString -> [(ByteString, ByteString)] -> Session SResponse
httpPost path params = srequest $ SRequest
    (setPath defaultRequest
        { requestMethod = methodPost
        , requestHeaders = [(hContentType, "application/x-www-form-urlencoded")]
        } path)
    (cs $ renderSimpleQuery False params)

httpDelete :: ByteString -> Session SResponse
httpDelete path = srequest (SRequest (setPath defaultRequest { requestMethod = methodDelete } path) "")

-- | Loads the page a redirect points to.
followRedirect :: SResponse -> Session SResponse
followRedirect response = case lookup "Location" (simpleHeaders response) of
    Just location -> httpGet (cs $ T.replace "http://localhost" "" (cs location))
    Nothing -> error ("Not a redirect: " <> show (simpleStatus response))

-- | Logs in to the admin with the given email and password.
logIn :: Text -> Text -> Session SResponse
logIn email password = httpPost "/admin/CreateSession" [("email", cs email), ("password", cs password)]

bodyText :: SResponse -> Text
bodyText = cs . simpleBody
