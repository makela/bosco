-- | How a customer's name and address are shown, wherever they are: the order
-- page, the invoice email and the admin.
module Application.Customer
    ( fullName
    , addressLines
    , reverseNameOf
    ) where

import qualified Data.Text as T

import IHP.Prelude
import Generated.Types

-- | "Maija Virtanen". A customer from before the name was split may have only
-- a first name.
fullName :: Customer -> Text
fullName customer = unwordsNonEmpty [customer.firstName, customer.lastName]

-- | The street on one line, the postal code and city on the next. Customers
-- from before the address was split may lack either line.
addressLines :: Customer -> [Text]
addressLines customer = filter (not . T.null)
    [ T.strip customer.streetAddress
    , unwordsNonEmpty [customer.postalCode, customer.city]
    ]

-- | Lower-cased last name, then first name, e.g. "virtanen maija". Customers
-- are listed, sorted and de-duplicated by this, so every code path that saves
-- a customer must set it.
reverseNameOf :: Text -> Text -> Text
reverseNameOf firstName lastName = toLower (unwordsNonEmpty [lastName, firstName])

unwordsNonEmpty :: [Text] -> Text
unwordsNonEmpty = T.unwords . concatMap T.words
