module Application.Helper.Controller where

import Data.Char (isDigit)
import qualified Data.Text as T

import IHP.ControllerPrelude

import Application.Localization

-- Here you can add functions which are available in all your controllers

-- | Case-insensitive substring search. The query is plain text, not a
-- pattern, so any characters (parentheses, dots, ...) are safe.
matchesSearch :: Text -> Text -> Bool
matchesSearch q text = T.null q' || toLower q' `T.isInfixOf` toLower text
    where q' = T.strip q

-- | A phone number of any country with its country code, or a Finnish one
-- without. Spaces or hyphens may split the digits into groups.
--
-- * International: + or 00, then the country code (which never starts with
--   0) and the number, 7-15 digits in all, e.g. "+39 333 123 4567" or
--   "0039 333 123 4567".
-- * Finnish with the country code but no +: 358..., 9-12 digits.
-- * Finnish local: 0..., 7-10 digits.
isPhone :: Text -> ValidatorResult
isPhone text
    | Just rest <- international, wellFormed rest, not ("0" `T.isPrefixOf` rest), digitsBetween rest 7 15 = Success
    | Just _ <- international = invalid
    | wellFormed stripped, "3" `T.isPrefixOf` stripped, digitsBetween stripped 9 12 = Success
    | wellFormed stripped, "0" `T.isPrefixOf` stripped, digitsBetween stripped 7 10 = Success
    | otherwise = invalid
    where
        invalid = Failure (l10nText LInvalidPhone)
        stripped = T.strip text
        international = T.stripPrefix "+" stripped <|> T.stripPrefix "00" stripped
        wellFormed number = not (T.null number)
            && isDigit (T.head number)
            && isDigit (T.last number)
            && T.all (\c -> isDigit c || c == ' ' || c == '-') number
        digitsBetween number lo hi = let n = T.length (T.filter isDigit number) in n >= lo && n <= hi

-- | A Finnish postal code: five digits
isPostalCode :: Text -> ValidatorResult
isPostalCode text
    | T.length stripped == 5 && T.all isDigit stripped = Success
    | otherwise = Failure (l10nText LInvalidPostalCode)
    where stripped = T.strip text
