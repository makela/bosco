//! The site's texts in Finnish, English and French, as in the IHP app's
//! `Application/Localization.hs`, which they were generated from. Each
//! instance serves one language, `APP_LOCALE`.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Locale {
    Fi,
    En,
    Fr,
}

impl Locale {
    /// From `APP_LOCALE`: fi, en or fr, Finnish when unset or empty
    pub fn parse(code: &str) -> Result<Self, String> {
        match code {
            "" | "fi" => Ok(Self::Fi),
            "en" => Ok(Self::En),
            "fr" => Ok(Self::Fr),
            other => Err(format!(
                "APP_LOCALE should be one of fi, en, fr, got {other}"
            )),
        }
    }

    /// For the html lang attribute
    pub fn code(self) -> &'static str {
        match self {
            Self::Fi => "fi",
            Self::En => "en",
            Self::Fr => "fr",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Text {
    BillingName,
    CheckOrderAndResubmit,
    City,
    /// The demo banner's invitation to the admin: the text before the
    /// link, the link's and the text after it
    DemoAdminAfter,
    DemoAdminBefore,
    DemoAdminLink,
    DemoBanner,
    DemoDoNotPay,
    DemoNoEmail,
    DetailsSaved,
    Email,
    FieldRequired,
    FillOrder,
    FirstName,
    InvalidEmail,
    InvalidPhone,
    InvalidPostalCode,
    Invoice,
    InvoiceCancelled,
    InvoicePaid,
    LastName,
    LeaveEmpty,
    NoLongerAvailable,
    NoProductsSelected,
    OrderForm,
    OrderingClosed,
    OrderingNotOpen,
    OrderSent,
    PageNotFound,
    PageNotFoundTitle,
    PaymentInstructions,
    PaymentSentToEmail,
    Phone,
    Pieces,
    PostalCode,
    SiteDescription,
    SiteTitle,
    StreetAddress,
    Submit,
    Subscribe,
    SubscribeToNewsLetter,
    Total,
}

impl Text {
    pub fn text(self, locale: Locale) -> &'static str {
        match (self, locale) {
            (Text::Submit, Locale::Fi) => "Tilaa",
            (Text::Submit, Locale::En) => "Order",
            (Text::Submit, Locale::Fr) => "Commander",
            (Text::OrderForm, Locale::Fi) => "Tilauslomake",
            (Text::OrderForm, Locale::En) => "Order form",
            (Text::OrderForm, Locale::Fr) => "Bon de commande",
            (Text::FirstName, Locale::Fi) => "Etunimi",
            (Text::FirstName, Locale::En) => "First name",
            (Text::FirstName, Locale::Fr) => "Prénom",
            (Text::LastName, Locale::Fi) => "Sukunimi",
            (Text::LastName, Locale::En) => "Last name",
            (Text::LastName, Locale::Fr) => "Nom",
            (Text::BillingName, Locale::Fi) => "Nimi laskulle / Yrityksen nimi",
            (Text::BillingName, Locale::En) => "Name on the invoice / Company name",
            (Text::BillingName, Locale::Fr) => "Nom sur la facture / Nom de l'entreprise",
            (Text::Email, Locale::Fi) => "Sähköposti",
            (Text::Email, Locale::En) => "Email",
            (Text::Email, Locale::Fr) => "E-mail",
            (Text::Phone, Locale::Fi) => "Puhelinnumero",
            (Text::Phone, Locale::En) => "Phone",
            (Text::Phone, Locale::Fr) => "Téléphone",
            (Text::StreetAddress, Locale::Fi) => "Katuosoite",
            (Text::StreetAddress, Locale::En) => "Street address",
            (Text::StreetAddress, Locale::Fr) => "Adresse",
            (Text::PostalCode, Locale::Fi) => "Postinumero",
            (Text::PostalCode, Locale::En) => "Postal code",
            (Text::PostalCode, Locale::Fr) => "Code postal",
            (Text::City, Locale::Fi) => "Postitoimipaikka",
            (Text::City, Locale::En) => "City",
            (Text::City, Locale::Fr) => "Ville",
            (Text::Subscribe, Locale::Fi) => "Tilaa",
            (Text::Subscribe, Locale::En) => "Subscribe",
            (Text::Subscribe, Locale::Fr) => "S'abonner",
            (Text::SubscribeToNewsLetter, Locale::Fi) => "Tilaa uutiskirje",
            (Text::SubscribeToNewsLetter, Locale::En) => "Subscribe to news letter",
            (Text::SubscribeToNewsLetter, Locale::Fr) => "S'abonner à la newsletter",
            (Text::FillOrder, Locale::Fi) => "Täytä tilaus",
            (Text::FillOrder, Locale::En) => "Make a new order",
            (Text::FillOrder, Locale::Fr) => "Passer une commande",
            (Text::Invoice, Locale::Fi) => "Lasku",
            (Text::Invoice, Locale::En) => "Invoice",
            (Text::Invoice, Locale::Fr) => "Facture",
            (Text::Total, Locale::Fi) => "Yhteensä",
            (Text::Total, Locale::En) => "Total",
            (Text::Total, Locale::Fr) => "Total",
            (Text::PaymentInstructions, Locale::Fi) => "Maksuohjeet",
            (Text::PaymentInstructions, Locale::En) => "Payment instructions",
            (Text::PaymentInstructions, Locale::Fr) => "Instructions de paiement",
            (Text::PaymentSentToEmail, Locale::Fi) => "Lasku on lähetetty myös sähköpostiinne.",
            (Text::PaymentSentToEmail, Locale::En) => {
                "The invoice has been sent to your email as well."
            }
            (Text::PaymentSentToEmail, Locale::Fr) => {
                "La facture vous a également été envoyée par e-mail."
            }
            (Text::NoLongerAvailable, Locale::Fi) => {
                "Tilausta ei lähetetty, koska nämä tuotteet eivät ole enää tilattavissa:"
            }
            (Text::NoLongerAvailable, Locale::En) => {
                "Your order was not sent because these products are no longer available:"
            }
            (Text::NoLongerAvailable, Locale::Fr) => {
                "Votre commande n'a pas été envoyée, car ces produits ne sont plus disponibles\u{a0}:"
            }
            (Text::CheckOrderAndResubmit, Locale::Fi) => {
                "Ne on poistettu lomakkeelta. Tarkista tilauksesi ja lähetä se uudelleen."
            }
            (Text::CheckOrderAndResubmit, Locale::En) => {
                "They have been removed from the form. Please check your order and send it again."
            }
            (Text::CheckOrderAndResubmit, Locale::Fr) => {
                "Ils ont été retirés du formulaire. Veuillez vérifier votre commande et l'envoyer à nouveau."
            }
            (Text::OrderingClosed, Locale::Fi) => {
                "Tilaustasi ei lähetetty, koska tilaukset on suljettu."
            }
            (Text::OrderingClosed, Locale::En) => {
                "Your order was not sent because ordering has closed."
            }
            (Text::OrderingClosed, Locale::Fr) => {
                "Votre commande n'a pas été envoyée, car les commandes sont closes."
            }
            (Text::OrderingNotOpen, Locale::Fi) => "Tilaaminen ei ole tällä hetkellä mahdollista.",
            (Text::OrderingNotOpen, Locale::En) => "Ordering is not open at the moment.",
            (Text::OrderingNotOpen, Locale::Fr) => {
                "Il n'est pas possible de commander pour le moment."
            }
            (Text::NoProductsSelected, Locale::Fi) => "Valitse vähintään yksi tuote.",
            (Text::NoProductsSelected, Locale::En) => "Please choose at least one product.",
            (Text::NoProductsSelected, Locale::Fr) => "Veuillez choisir au moins un produit.",
            (Text::InvoiceCancelled, Locale::Fi) => "Lasku on mitätöity.",
            (Text::InvoiceCancelled, Locale::En) => "This invoice has been cancelled.",
            (Text::InvoiceCancelled, Locale::Fr) => "Cette facture a été annulée.",
            (Text::InvoicePaid, Locale::Fi) => "Lasku on maksettu.",
            (Text::InvoicePaid, Locale::En) => "This invoice has been paid.",
            (Text::InvoicePaid, Locale::Fr) => "Cette facture a été payée.",
            (Text::OrderSent, Locale::Fi) => "Tilaus lähetetty",
            (Text::OrderSent, Locale::En) => "Order sent",
            (Text::OrderSent, Locale::Fr) => "Commande envoyée",
            (Text::DetailsSaved, Locale::Fi) => "Tiedot tallennettu",
            (Text::DetailsSaved, Locale::En) => "Details saved",
            (Text::DetailsSaved, Locale::Fr) => "Informations enregistrées",
            (Text::LeaveEmpty, Locale::Fi) => "Jätä tämä tyhjäksi",
            (Text::LeaveEmpty, Locale::En) => "Leave this empty",
            (Text::LeaveEmpty, Locale::Fr) => "Laissez ce champ vide",
            (Text::FieldRequired, Locale::Fi) => "Tämä kenttä vaaditaan",
            (Text::FieldRequired, Locale::En) => "This field is required",
            (Text::FieldRequired, Locale::Fr) => "Ce champ est obligatoire",
            (Text::InvalidEmail, Locale::Fi) => "Sähköposti on virheellinen",
            (Text::InvalidEmail, Locale::En) => "Invalid email address",
            (Text::InvalidEmail, Locale::Fr) => "Adresse e-mail invalide",
            (Text::InvalidPhone, Locale::Fi) => "Puhelinnumero on virheellinen",
            (Text::InvalidPhone, Locale::En) => "Invalid phone number",
            (Text::InvalidPhone, Locale::Fr) => "Numéro de téléphone invalide",
            (Text::InvalidPostalCode, Locale::Fi) => "Postinumerossa on viisi numeroa",
            (Text::InvalidPostalCode, Locale::En) => "A postal code has five digits",
            (Text::InvalidPostalCode, Locale::Fr) => "Un code postal a cinq chiffres",
            (Text::Pieces, Locale::Fi) => "kpl",
            (Text::Pieces, Locale::En) => "pcs",
            (Text::Pieces, Locale::Fr) => "pcs",
            (Text::SiteTitle, Locale::Fi) => "Bosco Falconeria Öljytilaus",
            (Text::SiteTitle, Locale::En) => "Bosco Falconeria Olive Oil Order",
            (Text::SiteTitle, Locale::Fr) => "Bosco Falconeria – Commande d'huile d'olive",
            (Text::SiteDescription, Locale::Fi) => "Bosco Falconerian öljytilauslomake",
            (Text::SiteDescription, Locale::En) => "Bosco Falconeria olive oil order form",
            (Text::SiteDescription, Locale::Fr) => {
                "Bon de commande d'huile d'olive Bosco Falconeria"
            }
            (Text::DemoAdminBefore, Locale::Fi) => "Kokeile myös ",
            (Text::DemoAdminLink, Locale::Fi) => "hallintaa",
            (Text::DemoAdminAfter, Locale::Fi) => {
                ": kirjaudu yhdellä napsautuksella ylläpitäjänä, jakelijana tai markkinoijana."
            }
            (Text::DemoAdminBefore, Locale::En) => "Try the ",
            (Text::DemoAdminLink, Locale::En) => "admin",
            (Text::DemoAdminAfter, Locale::En) => {
                " too: log in with one click as an admin, a delivery person or a promoter."
            }
            (Text::DemoAdminBefore, Locale::Fr) => "Essayez aussi l'",
            (Text::DemoAdminLink, Locale::Fr) => "administration",
            (Text::DemoAdminAfter, Locale::Fr) => {
                "\u{a0}: connectez-vous en un clic comme administrateur, livreur ou promoteur."
            }
            (Text::DemoBanner, Locale::Fi) => {
                "Tämä on esittelyversio. Tilaukset eivät ole oikeita, eikä mitään toimiteta tai laskuteta. Käytä keksittyjä tietoja."
            }
            (Text::DemoBanner, Locale::En) => {
                "This is a demo. Orders are not real, and nothing will be shipped or billed. Please use made-up details."
            }
            (Text::DemoBanner, Locale::Fr) => {
                "Ceci est une démo. Les commandes ne sont pas réelles\u{a0}: rien ne sera livré ni facturé. Utilisez des coordonnées fictives."
            }
            (Text::DemoDoNotPay, Locale::Fi) => "Esittelylasku – älä maksa.",
            (Text::DemoDoNotPay, Locale::En) => "Demo invoice – do not pay.",
            (Text::DemoDoNotPay, Locale::Fr) => "Facture de démonstration – ne pas payer.",
            (Text::DemoNoEmail, Locale::Fi) => "Esittelyversio ei lähetä laskua sähköpostiin.",
            (Text::DemoNoEmail, Locale::En) => "The demo does not send the invoice to your email.",
            (Text::DemoNoEmail, Locale::Fr) => "La démo n'envoie pas la facture par e-mail.",
            (Text::PageNotFoundTitle, Locale::Fi) => "Sivua ei löytynyt",
            (Text::PageNotFoundTitle, Locale::En) => "Page not found",
            (Text::PageNotFoundTitle, Locale::Fr) => "Page introuvable",
            (Text::PageNotFound, Locale::Fi) => {
                "Sivua ei löytynyt tai se ei ole juuri nyt käytettävissä."
            }
            (Text::PageNotFound, Locale::En) => {
                "The page was not found, or it is not available right now."
            }
            (Text::PageNotFound, Locale::Fr) => {
                "Cette page est introuvable ou n'est pas disponible pour le moment."
            }
        }
    }
}
