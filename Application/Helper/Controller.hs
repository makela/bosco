module Application.Helper.Controller where

import Data.Char (isDigit)
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

-- | A Finnish or international phone number: an optional leading +, then
-- digits, which spaces or hyphens may split into groups. Numbers starting
-- with + or a country code (3...) have 9-12 digits, local ones (0...) 7-10.
isPhone :: Text -> ValidatorResult
isPhone text
    | wellFormed, "+" `T.isPrefixOf` stripped, digitsBetween 9 12 = Success
    | wellFormed, "3" `T.isPrefixOf` stripped, digitsBetween 9 12 = Success
    | wellFormed, "0" `T.isPrefixOf` stripped, digitsBetween 7 10 = Success
    | otherwise = Failure "Puhelinnumero on virheellinen"
    where
        stripped = T.strip text
        number = fromMaybe stripped (T.stripPrefix "+" stripped)
        wellFormed = not (T.null number)
            && isDigit (T.head number)
            && isDigit (T.last number)
            && T.all (\c -> isDigit c || c == ' ' || c == '-') number
        digitCount = T.length (T.filter isDigit number)
        digitsBetween lo hi = digitCount >= lo && digitCount <= hi
