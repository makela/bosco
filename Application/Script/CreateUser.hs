#!/usr/bin/env run-script
module Application.Script.CreateUser where

import           Application.Script.Prelude

run :: Script
run = do
    let user = newRecord @User
    user
        |> set #email "tt.makela@gmail.com"
        |> set #passwordHash "REMOVED-PASSWORD-HASH"
        |> createRecord
    putStrLn "User created"
    pure ()
