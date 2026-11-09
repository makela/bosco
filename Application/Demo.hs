-- | A public demo (APP_DEMO, see nix/module.nix): whether this instance is
-- one, and the admin logins its login page offers to everyone.
module Application.Demo
    ( isDemo
    , DemoLogin (..)
    , demoLogins
    , demoLogin
    , isDemoUser
    , ensureDemoUser
    , demoPaymentDetails
    ) where

import IHP.ControllerPrelude
import IHP.FrameworkConfig (ConfigProvider)

import Application.Settings (DemoMode (..))
import Generated.Types

-- | Whether this instance is a public demo
isDemo :: (?context :: context, ConfigProvider context) => Bool
isDemo = let DemoMode demo = getAppConfig @DemoMode in demo

-- | A login anyone can use on the demo's login page, one per role
data DemoLogin = DemoLogin
    { role :: Text
    , label :: Text
    , email :: Text
    , isAdmin :: Bool
    , isDeliverer :: Bool
    , isPromoter :: Bool
    }

demoLogins :: [DemoLogin]
demoLogins =
    [ DemoLogin { role = "admin", label = "Admin", email = "admin@demo.invalid", isAdmin = True, isDeliverer = False, isPromoter = False }
    , DemoLogin { role = "orders", label = "Delivery person", email = "orders@demo.invalid", isAdmin = False, isDeliverer = True, isPromoter = False }
    , DemoLogin { role = "promoter", label = "Promoter", email = "promoter@demo.invalid", isAdmin = False, isDeliverer = False, isPromoter = True }
    ]

demoLogin :: Text -> Maybe DemoLogin
demoLogin wanted = find (\login -> login.role == wanted) demoLogins

isDemoUser :: User -> Bool
isDemoUser user = any (\login -> login.email == user.email) demoLogins

-- | The demo login's user, made on its first use. Its password is random
-- and never shown: the login page's buttons log in without one, so nobody
-- can lock the account by typing wrong passwords. Each use unlocks it all
-- the same, in case it was locked before.
ensureDemoUser :: (?modelContext :: ModelContext) => DemoLogin -> IO User
ensureDemoUser login = do
    existing <- query @User |> filterWhere (#email, login.email) |> fetchOneOrNothing
    case existing of
        Just user -> user
            |> setRoles
            |> set #lockedAt Nothing
            |> set #failedLoginAttempts 0
            |> updateRecord
        Nothing -> do
            password <- generateAuthenticationToken
            passwordHash <- hashPassword password
            newRecord @User
                |> set #email login.email
                |> set #passwordHash passwordHash
                |> setRoles
                |> createRecord
  where
    setRoles user = user
        |> set #isAdmin login.isAdmin
        |> set #isDeliverer login.isDeliverer
        |> set #isPromoter login.isPromoter

-- | The only payment details a demo shows: an obviously fake account. Its
-- invoices show these whatever the database holds, and its admin can't
-- change them, so nobody can put their own account on the demo's invoices.
demoPaymentDetails :: Text
demoPaymentDetails = intercalate "\n\n"
    [ "Bosco Falconeria (demo)"
    , "IBAN FI00 0000 0000 0000 00"
    , "BIC DEMOFIHH"
    ]
