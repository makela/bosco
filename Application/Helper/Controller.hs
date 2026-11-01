module Application.Helper.Controller where

import qualified Data.Text as T

import IHP.ControllerPrelude

-- Here you can add functions which are available in all your controllers

-- | Lower-cased name with its words reversed, e.g. "Maija Virtanen"
-- becomes "virtanen maija". Customers are listed and de-duplicated by
-- this, so every code path that saves a customer must set it.
reverseNameOf :: Text -> Text
reverseNameOf = toLower . unwords . reverse . words

-- | Case-insensitive substring search. The query is plain text, not a
-- pattern, so any characters (parentheses, dots, ...) are safe.
matchesSearch :: Text -> Text -> Bool
matchesSearch q text = T.null q' || toLower q' `T.isInfixOf` toLower text
    where q' = T.strip q
