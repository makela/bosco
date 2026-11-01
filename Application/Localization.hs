module Application.Localization where

import IHP.Prelude

data Locale
  = FI
  | EN
  deriving (Eq, Show, Enum, Bounded)

defaultLocale :: Locale
defaultLocale = FI

-- | For the html lang attribute
localeCode :: Locale -> Text
localeCode FI = "fi"
localeCode EN = "en"

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
  | LInvoiceCancelled
  | LInvoicePaid
  | LOrderSent
  | LDetailsSaved
  | LFieldRequired
  | LInvalidEmail
  | LInvalidPhone
  | LPieces
  | LSiteTitle
  | LSiteDescription
  deriving (Eq, Show, Enum, Bounded)

l10nText :: Localizable -> Text
l10nText l = l10nText' l defaultLocale

l10nText' :: Localizable -> Locale -> Text
l10nText' LSubmit FI = "Tilaa"
l10nText' LSubmit EN = "Order"
l10nText' LOrderForm FI = "Tilauslomake"
l10nText' LOrderForm EN = "Order form"
l10nText' LName FI = "Nimi"
l10nText' LName EN = "Name"
l10nText' LEmail FI = "Sähköposti"
l10nText' LEmail EN = "Email"
l10nText' LPhone FI = "Puhelinnumero"
l10nText' LPhone EN = "Phone"
l10nText' LAddress FI = "Osoite"
l10nText' LAddress EN = "Address"
l10nText' LSubscribeToNewsLetter FI = "Tilaa uutiskirje"
l10nText' LSubscribeToNewsLetter EN = "Subscribe to news letter"
l10nText' LSubscribe FI = "Tilaa"
l10nText' LSubscribe EN = "Subscribe"
l10nText' LFillOrder FI = "Täytä tilaus"
l10nText' LFillOrder EN = "Make a new order"
l10nText' LInvoice FI = "Lasku"
l10nText' LInvoice EN = "Invoice"
l10nText' LTotal FI = "Yhteensä"
l10nText' LTotal EN = "Total"
l10nText' LPaymentInstructions FI = "Maksuohjeet"
l10nText' LPaymentInstructions EN = "Payment instructions"
l10nText' LPaymentSentToEmail FI = "Lasku on lähetetty myös sähköpostiinne."
l10nText' LPaymentSentToEmail EN = "The invoice has been sent to your email as well."
l10nText' LNoLongerAvailable FI = "Tilausta ei lähetetty, koska nämä tuotteet eivät ole enää tilattavissa:"
l10nText' LNoLongerAvailable EN = "Your order was not sent because these products are no longer available:"
l10nText' LCheckOrderAndResubmit FI = "Ne on poistettu lomakkeelta. Tarkista tilauksesi ja lähetä se uudelleen."
l10nText' LCheckOrderAndResubmit EN = "They have been removed from the form. Please check your order and send it again."
l10nText' LOrderingClosed FI = "Tilaustasi ei lähetetty, koska tilaukset on suljettu."
l10nText' LOrderingClosed EN = "Your order was not sent because ordering has closed."
l10nText' LOrderingNotOpen FI = "Tilaaminen ei ole tällä hetkellä mahdollista."
l10nText' LOrderingNotOpen EN = "Ordering is not open at the moment."
l10nText' LNoProductsSelected FI = "Valitse vähintään yksi tuote."
l10nText' LNoProductsSelected EN = "Please choose at least one product."
l10nText' LInvoiceCancelled FI = "Lasku on mitätöity."
l10nText' LInvoiceCancelled EN = "This invoice has been cancelled."
l10nText' LInvoicePaid FI = "Lasku on maksettu."
l10nText' LInvoicePaid EN = "This invoice has been paid."
l10nText' LOrderSent FI = "Tilaus lähetetty"
l10nText' LOrderSent EN = "Order sent"
l10nText' LDetailsSaved FI = "Tiedot tallennettu"
l10nText' LDetailsSaved EN = "Details saved"
l10nText' LFieldRequired FI = "Tämä kenttä vaaditaan"
l10nText' LFieldRequired EN = "This field is required"
l10nText' LInvalidEmail FI = "Sähköposti on virheellinen"
l10nText' LInvalidEmail EN = "Invalid email address"
l10nText' LInvalidPhone FI = "Puhelinnumero on virheellinen"
l10nText' LInvalidPhone EN = "Invalid phone number"
l10nText' LPieces FI = "kpl"
l10nText' LPieces EN = "pcs"
l10nText' LSiteTitle FI = "Bosco Falconeria Öljytilaus"
l10nText' LSiteTitle EN = "Bosco Falconeria Olive Oil Order"
l10nText' LSiteDescription FI = "Bosco Falconerian öljytilauslomake"
l10nText' LSiteDescription EN = "Bosco Falconeria olive oil order form"
