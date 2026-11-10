-- | The one order products and producers are shown in, everywhere: the
-- order form, orders and their emails, and the admin's lists.
module Application.Sorting
    ( productOrder
    , sortProducers
    ) where

import IHP.Prelude
import Generated.Types

-- | Products with an ordering number come first, lowest first; then by name,
-- and the cheaper (smaller) one first when two share a name.
productOrder :: (HasField "ordering" product (Maybe Int), HasField "name" product Text, HasField "price" product Int)
             => product -> (Bool, Maybe Int, Text, Int)
productOrder x = (isNothing x.ordering, x.ordering, toLower x.name, x.price)

-- | Bosco Falconeria first, then the other producers A to Z.
sortProducers :: [Producer] -> [Producer]
sortProducers = sortOn (\x -> (not (isBosco x), toLower x.name))

isBosco :: Producer -> Bool
isBosco x = x.name == "Bosco Falconeria"
