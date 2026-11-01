module Application.Helper.Controller where

import IHP.ControllerPrelude

-- Here you can add functions which are available in all your controllers

-- | Lower-cased name with its words reversed, e.g. "Maija Virtanen"
-- becomes "virtanen maija". Customers are listed and de-duplicated by
-- this, so every code path that saves a customer must set it.
reverseNameOf :: Text -> Text
reverseNameOf = toLower . unwords . reverse . words
