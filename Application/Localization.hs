module Application.Localization where

import IHP.Prelude

data Locale
  = FI
  | FR
  deriving (Eq, Show)

defaultLocale :: Locale
defaultLocale = FR

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
