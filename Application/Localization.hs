module Application.Localization where

import IHP.Prelude

data Locale
  = FI
  | FR
  deriving (Eq, Show)

defaultLocale :: Locale
defaultLocale = FI

data Localizable
  = LSubmit
  | LOrderForm
  | LName
  | LEmail
  | LPhone
  | LAddress
  | LSubscribe
  | LSubscribeToNewsLetter
  | LFillOrder
  | LInvoice
  | LTotal
  | LPaymentInstructions
  | LPaymentSentToEmail
  | LNoLongerAvailable
  | LCheckOrderAndResubmit
  | LOrderingClosed
  | LOrderingNotOpen
  | LNoProductsSelected

l10nText :: Localizable -> Text
l10nText l = l10nText' l defaultLocale

l10nText' :: Localizable -> Locale -> Text
l10nText' LSubmit FI = "Tilaa"
l10nText' LSubmit FR = "Order"
l10nText' LOrderForm FI = "Tilauslomake"
l10nText' LOrderForm FR = "Order form"
l10nText' LName FI = "Nimi"
l10nText' LName FR = "Name"
l10nText' LEmail FI = "Sähköposti"
l10nText' LEmail FR = "Email"
l10nText' LPhone FI = "Puhelinnumero"
l10nText' LPhone FR = "Phone"
l10nText' LAddress FI = "Osoite"
l10nText' LAddress FR = "Address"
l10nText' LSubscribeToNewsLetter FI = "Tilaa uutiskirje"
l10nText' LSubscribeToNewsLetter FR = "Subscribe to news letter"
l10nText' LSubscribe FI = "Tilaa"
l10nText' LSubscribe FR = "Subscribe"
l10nText' LFillOrder FI = "Täytä tilaus"
l10nText' LFillOrder FR = "Make a new order"
l10nText' LInvoice FI = "Lasku"
l10nText' LInvoice FR = "Invoice"
l10nText' LTotal FI = "Yhteensä"
l10nText' LTotal FR = "Total"
l10nText' LPaymentInstructions FI = "Maksuohjeet"
l10nText' LPaymentInstructions FR = "Payment instructions"
l10nText' LPaymentSentToEmail FI = "Lasku on lähetetty myös sähköpostiinne."
l10nText' LPaymentSentToEmail FR = "Payment has been sent to your email as well."
l10nText' LNoLongerAvailable FI = "Tilausta ei lähetetty, koska nämä tuotteet eivät ole enää tilattavissa:"
l10nText' LNoLongerAvailable FR = "Your order was not sent because these products are no longer available:"
l10nText' LCheckOrderAndResubmit FI = "Ne on poistettu lomakkeelta. Tarkista tilauksesi ja lähetä se uudelleen."
l10nText' LCheckOrderAndResubmit FR = "They have been removed from the form. Please check your order and send it again."
l10nText' LOrderingClosed FI = "Tilaustasi ei lähetetty, koska tilaukset on suljettu."
l10nText' LOrderingClosed FR = "Your order was not sent because ordering has closed."
l10nText' LOrderingNotOpen FI = "Tilaaminen ei ole tällä hetkellä mahdollista."
l10nText' LOrderingNotOpen FR = "Ordering is not open at the moment."
l10nText' LNoProductsSelected FI = "Valitse vähintään yksi tuote."
l10nText' LNoProductsSelected FR = "Please choose at least one product."
