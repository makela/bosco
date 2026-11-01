module Test.Admin.Users where

import IHP.ControllerPrelude

import Generated.Types

-- | Admin actions re-fetch the current user from the database, so the
-- user passed to 'withUser' has to exist there too.
createAdmin :: (?modelContext :: ModelContext) => IO User
createAdmin = createTestUser True

createTestUser :: (?modelContext :: ModelContext) => Bool -> IO User
createTestUser isAdmin = newRecord @User
    |> set #email "admin@example.com"
    |> set #passwordHash "not-a-real-hash"
    |> set #isAdmin isAdmin
    |> createRecord
