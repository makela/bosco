//! The privacy notice's default text in each language, in Markdown: what
//! the site shows until the admin publishes one, and what the admin's form
//! to write the first one starts from. The farm, Bosco Falconeria in
//! Sicily, is the controller; the local organizers who take orders and
//! deliver them act for it. The parts in [brackets] are each instance's to
//! fill in. Under Italian law: the Garante, and 10 years for the accounts
//! (art. 2220 of the Civil Code).

use crate::l10n::Locale;

pub fn default_text(locale: Locale) -> &'static str {
    match locale {
        Locale::Fi => FI,
        Locale::En => EN,
        Locale::Fr => FR,
    }
}

const FI: &str = r#"## Rekisterinpitäjä

Bosco Falconeria, [yrityksen virallinen nimi ja muoto], [osoite], Sisilia, Italia. ALV-numero (Partita IVA) [numero].

Tietosuoja-asiat: [tilan sähköpostiosoite]

## Mitä tietoja keräämme ja miksi

**Tilaukset.** Nimi, laskun nimi, sähköposti, puhelinnumero, osoite, mitä tilaat ja milloin, sekä onko tilaus maksettu ja toimitettu. Tarvitsemme näitä tilauksen toimittamiseen, laskuttamiseen ja toimituksesta kertomiseen (sopimuksen täyttäminen, EU:n yleisen tietosuoja-asetuksen 6 artiklan 1 kohdan b alakohta) sekä lain vaatimaan kirjanpitoon (6 artiklan 1 kohdan c alakohta). Ilman niitä emme voi ottaa tilausta vastaan.

**Uutiskirje.** Nimi ja sähköposti. Jos tilaat uutiskirjeen sen lomakkeella, perusteena on suostumuksesi (6 artiklan 1 kohdan a alakohta). Jos jätät tilauslomakkeen uutiskirjeruudun rastitetuksi, lähetämme sinulle uutisia omista tuotteistamme, jotka ovat samankaltaisia kuin tilaamasi (Italian tietosuojalain 130 §:n 4 momentti ja oikeutettu etu, 6 artiklan 1 kohdan f alakohta). Voit poistaa rastin tilatessasi ja perua uutiskirjeen milloin tahansa.

**Sivuston käyttö.** Palvelin pitää teknistä lokia (IP-osoite, avatut sivut) tietoturvan ja vikojen korjaamisen vuoksi (oikeutettu etu); lokit säilytetään enintään 30 päivää. Sivusto ei käytä seuranta- eikä analytiikkaevästeitä. Lomakkeen lähettämisen jälkeen yksi tekninen eväste näyttää ilmoituksen kerran.

## Kuka näkee tietosi

- Bosco Falconeria.
- Tilaukset Suomessa keräävät ja toimittavat paikalliset järjestäjät [nimi ja yhteystiedot]. He käsittelevät tietoja tilan puolesta ja vain tilauksia ja toimituksia varten (henkilötietojen käsittelijät, 28 artikla).
- Palvelin- ja sähköpostipalvelut [palveluntarjoajat], jotka ovat EU:ssa. Tietoja ei siirretä EU:n ja ETA:n ulkopuolelle.

Emme myy tietojasi emmekä anna niitä muiden markkinointiin.

## Kuinka kauan tietoja säilytetään

- Tilaukset ja laskut: 10 vuotta tilausvuoden lopusta, kuten Italian kirjanpitolaki vaatii (siviililain 2220 §). Sen jälkeen nimi ja yhteystiedot poistetaan.
- Uutiskirje: kunnes perut sen. Perumisen jälkeen säilytämme merkinnän perumisesta, jottei uutiskirjettä lähetetä sinulle uudestaan.

## Oikeutesi

Voit pyytää pääsyä tietoihisi, niiden oikaisemista tai poistamista, käsittelyn rajoittamista ja tietojesi siirtämistä, ja vastustaa käsittelyä (15–21 artikla). Voit perua suostumuksesi milloin tahansa. Uutiskirjeen voi perua sivulla [Peru uutiskirjeen tilaus](/Unsubscribe).

Lähetä pyynnöt osoitteeseen [tilan sähköpostiosoite]. Vastaamme kuukauden kuluessa.

Voit tehdä valituksen Italian tietosuojaviranomaiselle (Garante per la protezione dei dati personali, [garanteprivacy.it](https://www.garanteprivacy.it/)) tai asuinmaasi viranomaiselle, Suomessa tietosuojavaltuutetun toimistolle ([tietosuoja.fi](https://tietosuoja.fi/)).

Emme tee sinusta automaattisia päätöksiä emmekä profiloi sinua.
"#;

const EN: &str = r#"## Controller

Bosco Falconeria, [the business's legal name and form], [address], Sicily, Italy. VAT number (Partita IVA) [number].

Privacy contact: [the farm's email address]

## What we collect and why

**Orders.** Your name, the name on the invoice, email, phone, address, what you order and when, and whether it's paid and delivered. We need these to deliver your order, invoice it and tell you about its delivery (performing the contract, Article 6(1)(b) of the GDPR), and for the accounts the law requires us to keep (Article 6(1)(c)). Without them we can't take your order.

**Newsletter.** Your name and email. If you sign up on the newsletter form, on the basis of your consent (Article 6(1)(a)). If you order with the newsletter box ticked, we send you news about our own products similar to those you bought (Article 130(4) of the Italian Privacy Code, and legitimate interest, Article 6(1)(f)). You can untick the box when you order, and unsubscribe at any time.

**Using the site.** The server keeps technical logs (IP address, pages opened) for security and to fix faults (legitimate interest), for at most 30 days. The site uses no tracking or analytics cookies. After you send a form, one technical cookie shows a notice once.

## Who sees your details

- Bosco Falconeria.
- The local organizers who collect and deliver the orders in [country]: [name and contact details]. They handle your details on the farm's behalf, only for orders and deliveries (processors, Article 28).
- The server and email services, [providers], in the EU. Your details aren't transferred outside the EU and EEA.

We never sell your details or give them to others for their marketing.

## How long we keep them

- Orders and invoices: 10 years from the end of the year of the order, as Italian accounting law requires (Article 2220 of the Civil Code). After that, names and contact details are removed.
- Newsletter: until you unsubscribe. After that we keep a note that you left, so that it isn't sent to you again.

## Your rights

You can ask for access to your details, to correct or erase them, to restrict their use or to receive them in a portable form, and you can object to their use (Articles 15–21). You can withdraw your consent at any time. To leave the newsletter, use [Unsubscribe from the newsletter](/Unsubscribe).

Send requests to [the farm's email address]. We answer within a month.

You can complain to the Italian data protection authority (Garante per la protezione dei dati personali, [garanteprivacy.it](https://www.garanteprivacy.it/)) or to the authority of the country where you live.

We make no automated decisions about you and don't profile you.
"#;

const FR: &str = r#"## Responsable du traitement

Bosco Falconeria, [raison sociale et forme de l'entreprise], [adresse], Sicile, Italie. Numéro de TVA (Partita IVA) [numéro].

Contact pour la protection des données : [adresse e-mail de l'exploitation]

## Données collectées et finalités

**Commandes.** Votre nom, le nom sur la facture, votre e-mail, votre téléphone, votre adresse, ce que vous commandez et quand, et si la commande est payée et livrée. Nous en avons besoin pour livrer et facturer votre commande et vous informer de sa livraison (exécution du contrat, article 6, paragraphe 1, point b, du RGPD), et pour la comptabilité que la loi nous impose (article 6, paragraphe 1, point c). Sans elles, nous ne pouvons pas prendre votre commande.

**Newsletter.** Votre nom et votre e-mail. Si vous vous inscrivez avec le formulaire de la newsletter, sur la base de votre consentement (article 6, paragraphe 1, point a). Si vous commandez en laissant cochée la case de la newsletter, nous vous envoyons des nouvelles de nos propres produits semblables à ceux que vous avez achetés (article 130, paragraphe 4, du Code italien de la protection des données, et intérêt légitime, article 6, paragraphe 1, point f). Vous pouvez décocher la case en commandant et vous désabonner à tout moment.

**Utilisation du site.** Le serveur conserve brièvement des journaux techniques (adresse IP, pages ouvertes) pour la sécurité et la correction des pannes (intérêt légitime). Le site n'utilise aucun cookie de suivi ni de mesure d'audience. Après l'envoi d'un formulaire, un cookie technique affiche une fois un message.

## Qui voit vos données

- Bosco Falconeria.
- Les organisateurs locaux qui recueillent et livrent les commandes en [pays] : [nom et coordonnées]. Ils traitent vos données pour le compte de l'exploitation, uniquement pour les commandes et les livraisons (sous-traitants, article 28).
- Les services d'hébergement et d'e-mail, [prestataires], situés dans l'UE. Vos données ne sont pas transférées hors de l'UE et de l'EEE.

Nous ne vendons jamais vos données et ne les cédons à personne pour son marketing.

## Durée de conservation

- Commandes et factures : 10 ans à compter de la fin de l'année de la commande, comme l'exige la loi comptable italienne (article 2220 du Code civil). Ensuite, les noms et coordonnées sont supprimés.
- Newsletter : jusqu'à votre désabonnement. Nous gardons ensuite une trace de votre départ, pour ne plus vous l'envoyer.

## Vos droits

Vous pouvez demander l'accès à vos données, leur rectification ou leur effacement, la limitation de leur traitement ou leur portabilité, et vous opposer à leur traitement (articles 15 à 21). Vous pouvez retirer votre consentement à tout moment. Pour quitter la newsletter : [Se désabonner de la newsletter](/Unsubscribe).

Envoyez vos demandes à [adresse e-mail de l'exploitation]. Nous répondons dans un délai d'un mois.

Vous pouvez introduire une réclamation auprès de l'autorité italienne de protection des données (Garante per la protezione dei dati personali, [garanteprivacy.it](https://www.garanteprivacy.it/)) ou de celle de votre pays de résidence, en France la CNIL ([cnil.fr](https://www.cnil.fr/)).

Nous ne prenons aucune décision automatisée vous concernant et ne faisons pas de profilage.
"#;
