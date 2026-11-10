#!/usr/bin/env run-script
-- | Creates an admin login, or one with other roles. The email and password
-- come from the environment, so they never end up in the repository or in
-- the shell's history:
--
--   read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
--   ADMIN_EMAIL=you@example.com run-script Application/Script/CreateUser.hs
--
-- ROLES picks the roles, comma-separated, admin if not given: e.g.
-- ROLES=deliverer,promoter for a delivery person who is also a promoter.
-- See Application/Permission.hs for what each may do.
module Application.Script.CreateUser where

import qualified Data.Text as T

import IHP.EnvVar (envOrNothing)

import Application.Script.Prelude

run :: Script
run = do
    roles <- envOrNothing "ROLES" >>= either error pure . parseRoles . fromMaybe "admin"
    email <- setting "ADMIN_EMAIL"
    password <- setting "ADMIN_PASSWORD"
    existing <- query @User |> filterWhere (#email, email) |> fetchCount
    when (existing > 0) (error ("A user " <> cs email <> " exists already"))
    passwordHash <- hashPassword password
    _ <- newRecord @User
        |> set #email email
        |> set #passwordHash passwordHash
        |> set #isAdmin ("admin" `elem` roles)
        |> set #isDeliverer ("deliverer" `elem` roles)
        |> set #isPromoter ("promoter" `elem` roles)
        |> createRecord
    putStrLn ("Created " <> email <> " with the roles " <> intercalate ", " roles)

-- | "deliverer, promoter" is ["deliverer", "promoter"]. At least one role,
-- and only known ones: a user without a role could log in but do nothing.
parseRoles :: Text -> Either Text [Text]
parseRoles text = case filter (not . T.null) (map (T.toLower . T.strip) (T.splitOn "," text)) of
    [] -> Left "ROLES should name at least one of admin, deliverer, promoter"
    roles -> case filter (`notElem` knownRoles) roles of
        [] -> Right (nub roles)
        unknown -> Left ("Unknown roles " <> intercalate ", " unknown <> ", known: " <> intercalate ", " knownRoles)
  where knownRoles = ["admin", "deliverer", "promoter"]

-- | A setting that must be given. Checked here, before any query: IHP's env
-- only fails once its value is used, which in the middle of sending a query
-- leaves the database connection waiting forever.
setting :: ByteString -> IO Text
setting name = envOrNothing name >>= \case
    Just value | not (T.null (T.strip value)) -> pure value
    _ -> error ("Set " <> cs name <> ", see the top of Application/Script/CreateUser.hs")
