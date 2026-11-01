module Application.Localization where

import IHP.Prelude

data Locale
  = FI
  | EN
  | FR
  deriving (Eq, Show, Enum, Bounded)

defaultLocale :: Locale
defaultLocale = FI

-- | For the html lang attribute
localeCode :: Locale -> Text
localeCode FI = "fi"
localeCode EN = "en"
localeCode FR = "fr"

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
l10nText' LSubmit FR = "Commander"
l10nText' LOrderForm FI = "Tilauslomake"
l10nText' LOrderForm EN = "Order form"
l10nText' LOrderForm FR = "Bon de commande"
l10nText' LName FI = "Nimi"
l10nText' LName EN = "Name"
l10nText' LName FR = "Nom"
l10nText' LEmail FI = "Sähköposti"
l10nText' LEmail EN = "Email"
l10nText' LEmail FR = "E-mail"
l10nText' LPhone FI = "Puhelinnumero"
l10nText' LPhone EN = "Phone"
l10nText' LPhone FR = "Téléphone"
l10nText' LAddress FI = "Osoite"
l10nText' LAddress EN = "Address"
l10nText' LAddress FR = "Adresse"
l10nText' LSubscribeToNewsLetter FI = "Tilaa uutiskirje"
l10nText' LSubscribeToNewsLetter EN = "Subscribe to news letter"
l10nText' LSubscribeToNewsLetter FR = "S'abonner à la newsletter"
l10nText' LSubscribe FI = "Tilaa"
l10nText' LSubscribe EN = "Subscribe"
l10nText' LSubscribe FR = "S'abonner"
l10nText' LFillOrder FI = "Täytä tilaus"
l10nText' LFillOrder EN = "Make a new order"
l10nText' LFillOrder FR = "Passer une commande"
l10nText' LInvoice FI = "Lasku"
l10nText' LInvoice EN = "Invoice"
l10nText' LInvoice FR = "Facture"
l10nText' LTotal FI = "Yhteensä"
l10nText' LTotal EN = "Total"
l10nText' LTotal FR = "Total"
l10nText' LPaymentInstructions FI = "Maksuohjeet"
l10nText' LPaymentInstructions EN = "Payment instructions"
l10nText' LPaymentInstructions FR = "Instructions de paiement"
l10nText' LPaymentSentToEmail FI = "Lasku on lähetetty myös sähköpostiinne."
l10nText' LPaymentSentToEmail EN = "The invoice has been sent to your email as well."
l10nText' LPaymentSentToEmail FR = "La facture vous a également été envoyée par e-mail."
l10nText' LNoLongerAvailable FI = "Tilausta ei lähetetty, koska nämä tuotteet eivät ole enää tilattavissa:"
l10nText' LNoLongerAvailable EN = "Your order was not sent because these products are no longer available:"
l10nText' LNoLongerAvailable FR = "Votre commande n'a pas été envoyée, car ces produits ne sont plus disponibles :"
l10nText' LCheckOrderAndResubmit FI = "Ne on poistettu lomakkeelta. Tarkista tilauksesi ja lähetä se uudelleen."
l10nText' LCheckOrderAndResubmit EN = "They have been removed from the form. Please check your order and send it again."
l10nText' LCheckOrderAndResubmit FR = "Ils ont été retirés du formulaire. Veuillez vérifier votre commande et l'envoyer à nouveau."
l10nText' LOrderingClosed FI = "Tilaustasi ei lähetetty, koska tilaukset on suljettu."
l10nText' LOrderingClosed EN = "Your order was not sent because ordering has closed."
l10nText' LOrderingClosed FR = "Votre commande n'a pas été envoyée, car les commandes sont closes."
l10nText' LOrderingNotOpen FI = "Tilaaminen ei ole tällä hetkellä mahdollista."
l10nText' LOrderingNotOpen EN = "Ordering is not open at the moment."
l10nText' LOrderingNotOpen FR = "Il n'est pas possible de commander pour le moment."
l10nText' LNoProductsSelected FI = "Valitse vähintään yksi tuote."
l10nText' LNoProductsSelected EN = "Please choose at least one product."
l10nText' LNoProductsSelected FR = "Veuillez choisir au moins un produit."
l10nText' LInvoiceCancelled FI = "Lasku on mitätöity."
l10nText' LInvoiceCancelled EN = "This invoice has been cancelled."
l10nText' LInvoiceCancelled FR = "Cette facture a été annulée."
l10nText' LInvoicePaid FI = "Lasku on maksettu."
l10nText' LInvoicePaid EN = "This invoice has been paid."
l10nText' LInvoicePaid FR = "Cette facture a été payée."
l10nText' LOrderSent FI = "Tilaus lähetetty"
l10nText' LOrderSent EN = "Order sent"
l10nText' LOrderSent FR = "Commande envoyée"
l10nText' LDetailsSaved FI = "Tiedot tallennettu"
l10nText' LDetailsSaved EN = "Details saved"
l10nText' LDetailsSaved FR = "Informations enregistrées"
l10nText' LFieldRequired FI = "Tämä kenttä vaaditaan"
l10nText' LFieldRequired EN = "This field is required"
l10nText' LFieldRequired FR = "Ce champ est obligatoire"
l10nText' LInvalidEmail FI = "Sähköposti on virheellinen"
l10nText' LInvalidEmail EN = "Invalid email address"
l10nText' LInvalidEmail FR = "Adresse e-mail invalide"
l10nText' LInvalidPhone FI = "Puhelinnumero on virheellinen"
l10nText' LInvalidPhone EN = "Invalid phone number"
l10nText' LInvalidPhone FR = "Numéro de téléphone invalide"
l10nText' LPieces FI = "kpl"
l10nText' LPieces EN = "pcs"
l10nText' LPieces FR = "pcs"
l10nText' LSiteTitle FI = "Bosco Falconeria Öljytilaus"
l10nText' LSiteTitle EN = "Bosco Falconeria Olive Oil Order"
l10nText' LSiteTitle FR = "Bosco Falconeria – Commande d'huile d'olive"
l10nText' LSiteDescription FI = "Bosco Falconerian öljytilauslomake"
l10nText' LSiteDescription EN = "Bosco Falconeria olive oil order form"
l10nText' LSiteDescription FR = "Bon de commande d'huile d'olive Bosco Falconeria"
