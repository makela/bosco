-- | The history of the shop's texts: who changed which product or producer
-- text, when, and from what (the text_changes table)
module Application.TextHistory
    ( productTextChanges
    , producerTextChanges
    ) where

import IHP.ModelSupport (newRecord)
import IHP.Prelude
import Generated.Types

-- | A change for each of the product's texts that differs after the edit
productTextChanges :: User -> Product -> Product -> [TextChange]
productTextChanges user before after =
    map (set #productId (Just before.id)) (changes user (productTexts before) (productTexts after))

-- | A change for each of the producer's texts that differs after the edit
producerTextChanges :: User -> Producer -> Producer -> [TextChange]
producerTextChanges user before after =
    map (set #producerId (Just before.id)) (changes user (producerTexts before) (producerTexts after))

productTexts :: Product -> [(Text, Text)]
productTexts product =
    [("name", product.name), ("description", product.description), ("package", product.package)]

producerTexts :: Producer -> [(Text, Text)]
producerTexts producer =
    [("name", producer.name), ("subject", producer.subject), ("description", producer.description)]

changes :: User -> [(Text, Text)] -> [(Text, Text)] -> [TextChange]
changes user before after =
    [ newRecord @TextChange
        |> set #userId user.id
        |> set #fieldName field
        |> set #textBefore old
        |> set #textAfter new
    | ((field, old), (_, new)) <- zip before after
    , old /= new
    ]
