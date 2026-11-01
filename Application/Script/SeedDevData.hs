#!/usr/bin/env run-script
-- | Fills the dev database with data to browse: orders from this season and
-- the two before it in every state, a returning customer, newsletter-only
-- subscribers, a payment instruction and two logins (admin and a delivery
-- person who only sees orders). The passwords are printed at the end.
--
-- Run with: make seed-dev
--
-- It refuses to run when the database already has orders, so it can't add
-- made-up orders to a database that holds real ones. No email jobs are
-- created, so nothing gets sent.
module Application.Script.SeedDevData where

import qualified Data.Text as T
import Data.Time.Calendar (toGregorian)
import Data.Time.Clock (addUTCTime, nominalDay, secondsToDiffTime)

import Application.Helper.Controller (reverseNameOf)
import Application.Script.Prelude

run :: Script
run = do
    existingOrders <- query @Order |> fetchCount
    when (existingOrders > 0) do
        error "The database already has orders; not seeding. Seed a fresh dev database instead."

    now <- getCurrentTime
    let (thisYear, _, _) = toGregorian (utctDay now)

    passwords <- withTransaction do
        ensureWelcomeMessage
        ensurePaymentInstruction
        forM_ (seedOrders now thisYear) createSeedOrder
        forM_ newsletterSubscribers \name -> createSeedCustomer name (emailFor name) "" ""
        admin <- createLogin "admin@example.com" True
        delivery <- createLogin "jakelija@example.com" False
        pure [admin, delivery]

    putStrLn "Seeded the dev database. Logins at /admin/NewSession:"
    forM_ passwords \(email, password) -> putStrLn ("  " <> email <> "  " <> password)

-- | An order as it is seeded. The status fields are days after ordering
-- (Nothing = not yet), and items are (product name, package, quantity).
data SeedOrder = SeedOrder
    { customer :: Text
    , phone :: Text
    , address :: Text
    , orderedAt :: UTCTime
    , items :: [(Text, Text, Int)]
    , invoicedAfter, paidAfter, deliveredAfter, cancelledAfter :: Maybe Integer
    , priceFactor :: Double
      -- ^ Below 1 for older seasons, to show that orders keep their prices
    }

seedOrders :: UTCTime -> Integer -> [SeedOrder]
seedOrders now thisYear =
    -- Two seasons ago: everything handled, at about 10% lower prices
    [ old 2 10 8 maija [oil3 1, almonds 2] (Just 3) (Just 9) (Just 40)
    , old 2 10 15 juhani [oil3 2, ("Kahvisuklaa", "60 g", 4)] (Just 3) (Just 6) (Just 35)
    , old 2 10 22 aino [basil 2, marzipan 1, ("Suolasuklaa", "60 g", 3)] (Just 2) (Just 12) (Just 30)
    , old 2 11 2 pekka [oil250 6] (Just 1) (Just 4) (Just 25)
    -- Last season: mostly handled, one cancelled
    , old 1 10 6 maija [oil3 1, ("Bronten pistaasipähkinöitä, kuivattuja", "100 g", 2)] (Just 2) (Just 5) (Just 38)
    , old 1 10 12 elina [vinegar500 2, mint 1, ("Chilisuklaa", "60 g", 2)] (Just 2) (Just 10) (Just 36)
    , old 1 10 19 juhani [oil3 2] (Just 1) (Just 8) (Just 33)
    , (old 1 10 25 sanna [raisins 2, capers 2] Nothing Nothing Nothing) { cancelledAfter = Just 2 }
    , old 1 11 3 ville [oil250 4, ("Inkiväärisuklaa", "60 g", 2), ("Kanelisuklaa", "60 g", 2)] (Just 1) (Just 3) (Just 28)
    -- This season (the last four weeks): every state
    , recent 27 maija [oil3 2, almonds 1, ("Sesam-appelsiinisuklaa", "60 g", 2)] (Just 1) (Just 6) (Just 25)
    , recent 23 juhani [oil3 1, ("Valkoviinietikkaa", "250 ml lasipullo", 3)] (Just 2) (Just 9) Nothing
    , recent 18 aino [basil 1, mint 1, marzipan 2] (Just 1) Nothing Nothing
    , recent 14 tuomas [oil250 3, ("Chilisuklaa", "60 g", 1), ("Suolasuklaa", "60 g", 1)] (Just 1) Nothing (Just 10)
    , (recent 10 elina [("Bronten pistaasipähkinöitä, kuivattuja", "100 g", 3), raisins 1] Nothing Nothing Nothing) { cancelledAfter = Just 3 }
    , recent 5 kaisa [oil3 1, capers 2, ("Inkiväärisuklaa", "60 g", 2)] Nothing Nothing Nothing
    , recent 2 olli [vinegar500 1] Nothing Nothing Nothing
    ]
  where
    old yearsAgo month day (name, phone, address) items invoiced paid delivered = SeedOrder
        { customer = name, phone, address, items
        , orderedAt = UTCTime (fromGregorian (thisYear - yearsAgo) month day) (secondsToDiffTime (16 * 3600))
        , invoicedAfter = invoiced, paidAfter = paid, deliveredAfter = delivered, cancelledAfter = Nothing
        , priceFactor = if yearsAgo >= 2 then 0.9 else 1
        }
    recent daysAgo (name, phone, address) items invoiced paid delivered = SeedOrder
        { customer = name, phone, address, items
        , orderedAt = addUTCTime (negate (fromInteger daysAgo) * nominalDay) now
        , invoicedAfter = invoiced, paidAfter = paid, deliveredAfter = delivered, cancelledAfter = Nothing
        , priceFactor = 1
        }
    maija = ("Maija Virtanen", "040 123 4567", "Mannerheimintie 12 B 7, 00100 Helsinki")
    juhani = ("Juhani Korhonen", "050-765 4321", "Hämeenkatu 3 A 1, 33100 Tampere")
    aino = ("Aino Mäkinen", "+358 44 987 6543", "Puistokatu 8, 20100 Turku")
    pekka = ("Pekka Laine", "045 222 3344", "Rantatie 21, 90100 Oulu")
    elina = ("Elina Nieminen", "0401112233", "Kauppakatu 15 C 22, 40100 Jyväskylä")
    sanna = ("Sanna Heikkinen", "044 555 6677", "Asemakatu 4, 70100 Kuopio")
    ville = ("Ville Hämäläinen", "+358 40 246 8101", "Satamakatu 9, 15100 Lahti")
    tuomas = ("Tuomas Lehtonen", "045-998 7766", "Kirkkokatu 30 A 5, 90100 Oulu")
    kaisa = ("Kaisa-Maria Järvinen", "050 333 4455", "Länsiväylä 101 D 44, 02160 Espoo")
    olli = ("Olli Koskinen", "+358 40 777 8899", "Torikatu 2, 28100 Pori")
    oil3 n = ("Oliiviöljyä", "3 l kanisteri", n)
    oil250 n = ("Oliiviöljyä", "250 ml lasipullo", n)
    almonds n = ("Luomumantelit, kuorellinen", "500g", n)
    basil n = ("Basilikankukkaviinietikkaa", "250 ml lasipullo", n)
    mint n = ("Minttu-laventeliviinietikkaa", "250 ml lasipullo", n)
    marzipan n = ("Luomumarsipaania", "250 g", n)
    vinegar500 n = ("Valkoviinietikkaa", "500 ml lasipullo", n)
    raisins n = ("Zibibbo rusinoita", "250 g", n)
    capers n = ("Luomukaprista suolassa", "200 g", n)

newsletterSubscribers :: [Text]
newsletterSubscribers = ["Leena Salminen", "Matti Rantanen", "Hanna Laaksonen"]

-- | firstname.lastname@example.com, without accents
emailFor :: Text -> Text
emailFor name = name
    |> toLower
    |> T.map (\case 'ä' -> 'a'; 'ö' -> 'o'; 'å' -> 'a'; c -> c)
    |> T.words
    |> \parts -> T.intercalate "." [head' parts, lastPart parts]
    |> (<> "@example.com")
    |> T.filter (/= '-')
  where
    head' = fromMaybe "" . head
    lastPart = fromMaybe "" . last

createSeedOrder :: (?modelContext :: ModelContext) => SeedOrder -> IO ()
createSeedOrder seed = do
    customer <- createSeedCustomer seed.customer (emailFor seed.customer) seed.phone seed.address
    let after days = fmap (\d -> addUTCTime (fromInteger d * nominalDay) seed.orderedAt) days
    order <- newRecord @Order
        |> set #customerId customer.id
        |> set #orderedAt seed.orderedAt
        |> set #invoicedAt (after seed.invoicedAfter)
        |> set #paidAt (after seed.paidAfter)
        |> set #deliveredAt (after seed.deliveredAfter)
        |> set #cancelledAt (after seed.cancelledAfter)
        |> createRecord
    forM_ seed.items \(name, package, quantity) -> do
        product <- query @Product
            |> filterWhere (#name, name)
            |> filterWhere (#package, package)
            |> fetchOneOrNothing
            >>= maybe (error ("No product " <> cs name <> " (" <> cs package <> ") in the fixtures")) pure
        let price = round (fromIntegral product.price * seed.priceFactor / 10) * 10
        newRecord @OrderedProduct
            |> set #orderId order.id
            |> set #productId product.id
            |> set #quantity quantity
            |> set #unitPrice price
            |> createRecord
            |> fmap (const ())

createSeedCustomer :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Text -> IO Customer
createSeedCustomer name email phone address = newRecord @Customer
    |> set #name name
    |> set #reverseName (reverseNameOf name)
    |> set #email email
    |> set #phone phone
    |> set #address address
    |> createRecord

-- | Opens ordering unless some welcome message already exists.
ensureWelcomeMessage :: (?modelContext :: ModelContext) => IO ()
ensureWelcomeMessage = do
    count <- query @WelcomeMessage |> fetchCount
    when (count == 0) do
        _ <- newRecord @WelcomeMessage
            |> set #text "Tervetuloa tilaamaan oliiviöljyä ja muita herkkuja Sisiliasta!"
            |> set #isOrderingEnabled True
            |> createRecord
        pure ()

ensurePaymentInstruction :: (?modelContext :: ModelContext) => IO ()
ensurePaymentInstruction = do
    count <- query @PaymentInstruction |> fetchCount
    when (count == 0) do
        _ <- newRecord @PaymentInstruction
            |> set #text "Bosco Falconeria (esimerkkitili)\n\nIBAN FI00 1234 5600 0007 85\n\nBIC ESIMFIHH\n\nMaksun eräpäivä on **15. marraskuuta**."
            |> createRecord
        pure ()

-- | Creates a login with a random password, or skips an existing one.
createLogin :: (?modelContext :: ModelContext) => Text -> Bool -> IO (Text, Text)
createLogin email isAdmin = do
    existing <- query @User |> filterWhere (#email, email) |> fetchCount
    if existing > 0
        then pure (email, "(already existed, password unchanged)")
        else do
            password <- generateAuthenticationToken |> fmap (T.take 16)
            passwordHash <- hashPassword password
            _ <- newRecord @User
                |> set #email email
                |> set #passwordHash passwordHash
                |> set #isAdmin isAdmin
                |> createRecord
            pure (email <> (if isAdmin then " (admin)" else " (orders only)"), password)
