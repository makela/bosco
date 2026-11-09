module Test.Admin.Users where

import IHP.ControllerPrelude

import Generated.Types

-- | Admin actions re-fetch the current user from the database, so the
-- user passed to 'withUser' has to exist there too.
createAdmin :: (?modelContext :: ModelContext) => IO User
createAdmin = createTestUser True

-- | An admin, or a delivery person, as every other user used to be
createTestUser :: (?modelContext :: ModelContext) => Bool -> IO User
createTestUser isAdmin = createUserWithRoles isAdmin (not isAdmin) False

createDeliverer, createPromoter :: (?modelContext :: ModelContext) => IO User
createDeliverer = createUserWithRoles False True False
createPromoter = createUserWithRoles False False True

createUserWithRoles :: (?modelContext :: ModelContext) => Bool -> Bool -> Bool -> IO User
createUserWithRoles isAdmin isDeliverer isPromoter = newRecord @User
    |> set #email "admin@example.com"
    |> set #passwordHash "not-a-real-hash"
    |> set #isAdmin isAdmin
    |> set #isDeliverer isDeliverer
    |> set #isPromoter isPromoter
    |> createRecord
