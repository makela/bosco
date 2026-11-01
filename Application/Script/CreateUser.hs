#!/usr/bin/env run-script
-- | Creates an admin login. The email and password come from the
-- environment, so they never end up in the repository or in the shell's
-- history:
--
--   read -rs ADMIN_PASSWORD && export ADMIN_PASSWORD
--   ADMIN_EMAIL=you@example.com run-script Application/Script/CreateUser.hs
module Application.Script.CreateUser where

import qualified Data.Text as T

import IHP.EnvVar (envOrNothing)

import Application.Script.Prelude

run :: Script
run = do
    email <- setting "ADMIN_EMAIL"
    password <- setting "ADMIN_PASSWORD"
    existing <- query @User |> filterWhere (#email, email) |> fetchCount
    when (existing > 0) (error ("A user " <> cs email <> " exists already"))
    passwordHash <- hashPassword password
    _ <- newRecord @User
        |> set #email email
        |> set #passwordHash passwordHash
        |> set #isAdmin True
        |> createRecord
    putStrLn ("Created the admin " <> email)

-- | A setting that must be given. Checked here, before any query: IHP's env
-- only fails once its value is used, which in the middle of sending a query
-- leaves the database connection waiting forever.
setting :: ByteString -> IO Text
setting name = envOrNothing name >>= \case
    Just value | not (T.null (T.strip value)) -> pure value
    _ -> error ("Set " <> cs name <> ", see the top of Application/Script/CreateUser.hs")
