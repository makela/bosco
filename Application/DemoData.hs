-- | The data of a public demo (APP_DEMO), reset every night by
-- Application/Script/ResetDemo.hs: the catalog from Fixtures.sql, fake
-- payment details and a few seasons of made-up orders. Older seasons have
-- lower prices, since each product's price went up a little most years.
--
-- The orders come from a seeded generator, so the same seed and time give
-- the same orders, and the tests can check them.
module Application.DemoData
    ( resetDemoData
    , fixtureInserts
    , CatalogItem (..)
    , DemoCustomer (..)
    , DemoOrder (..)
    , DemoLine (..)
    , demoOrders
    , seasonPrices
    , seasons
    , seedFor
    ) where

import Control.Monad (filterM, replicateM)
import Data.Bits (shiftR, xor)
import Data.Char (isSpace)
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Text as T
import Data.Time.Calendar (addGregorianYearsClip, toModifiedJulianDay)
import Data.Time.Clock (addUTCTime, diffUTCTime, nominalDay)
import Data.String (fromString)
import Data.Word (Word64)

import IHP.ControllerPrelude

import Application.Demo (demoPaymentDetails)
import Application.Customer (reverseNameOf)
import Application.Localization
import Generated.Types

-- | The olive oils, four times as popular as the other products. By id, as
-- the catalogs in other languages (Fixtures.en.sql) have the same ids.
oliveOils :: [Id Product]
oliveOils = map textToId
    [ "61db0ec5-698a-4b48-b19b-995d41472bb1" :: Text -- 250 ml
    , "0fa0cd0f-921a-429e-a184-3a9a547f0990" -- 3 l
    ]

-- | How many ordering seasons the demo has: this one and the three before
seasons :: Int
seasons = 4

-- | Empties the demo's data and fills it again, in one transaction. Logins
-- are kept, so whoever is logged in stays logged in. Returns the number of
-- orders made.
resetDemoData :: (?modelContext :: ModelContext) => Text -> Word64 -> UTCTime -> IO Int
resetDemoData fixtures seed now = withTransaction do
    forM_ emptiedTables \table -> unsafeSqlExecDiscardResult (fromString ("DELETE FROM " <> table)) ()
    forM_ (fixtureInserts fixtures) \statement -> unsafeSqlExecDiscardResult (fromString (cs statement)) ()
    _ <- newRecord @PaymentInstruction |> set #text demoPaymentDetails |> createRecord
    products <- query @Product |> filterWhere (#enabled, True) |> fetch
    let catalog = map (\p -> CatalogItem { productId = p.id, price = p.price }) products
        orders = demoOrders seed now catalog
    forM_ orders createDemoOrder
    forM_ newsletterSubscribers (createDemoCustomer . subscriberOnly)
    pure (length orders)
  where
    -- Children before parents, for the foreign keys
    emptiedTables =
        [ "text_changes", "email_order_jobs", "ordered_products", "orders", "customers"
        , "products", "producers", "welcome_messages", "payment_instructions"
        ]

-- | The INSERT statements of a pg_dump like Fixtures.sql. Its other
-- statements change session settings or need a superuser, and the rows
-- don't need them. Texts may hold line breaks and semicolons, so a
-- statement ends at the first semicolon outside quotes.
fixtureInserts :: Text -> [Text]
fixtureInserts sql = statements (cs sql) ""
    |> map (T.strip . cs)
    |> filter ("INSERT INTO " `T.isPrefixOf`)
  where
    -- The statement read so far is reversed in current
    statements :: String -> String -> [String]
    statements [] current = [reverse current | not (all isSpace current)]
    statements ('\'' : rest) current = let (quoted, after) = quote rest "'" in statements after (quoted <> current)
    statements ('-' : '-' : rest) current | all isSpace current = statements (dropWhile (/= '\n') rest) current
    statements (';' : rest) current = reverse (';' : current) : statements rest ""
    statements (c : rest) current = statements rest (c : current)
    -- Reads a quoted text up to its closing quote; '' is a quote inside it
    quote :: String -> String -> (String, String)
    quote ('\'' : '\'' : rest) read = quote rest ("''" <> read)
    quote ('\'' : rest) read = ('\'' : read, rest)
    quote (c : rest) read = quote rest (c : read)
    quote [] read = (read, [])

createDemoOrder :: (?modelContext :: ModelContext) => DemoOrder -> IO ()
createDemoOrder demo = do
    customer <- createDemoCustomer demo.customer
    order <- newRecord @Order
        |> set #customerId customer.id
        |> set #orderedAt demo.orderedAt
        |> set #invoicedAt demo.invoicedAt
        |> set #paidAt demo.paidAt
        |> set #deliveredAt demo.deliveredAt
        |> set #cancelledAt demo.cancelledAt
        |> createRecord
    forM_ demo.orderLines \line -> newRecord @OrderedProduct
        |> set #orderId order.id
        |> set #productId line.productId
        |> set #quantity line.quantity
        |> set #unitPrice line.unitPrice
        |> createRecord

-- | A newsletter subscriber gives only a name and an email
subscriberOnly :: DemoCustomer -> DemoCustomer
subscriberOnly DemoCustomer { firstName, lastName, email } = DemoCustomer
    { firstName, lastName, email, phone = "", streetAddress = "", postalCode = "", city = "" }

createDemoCustomer :: (?modelContext :: ModelContext) => DemoCustomer -> IO Customer
createDemoCustomer customer = newRecord @Customer
    |> set #firstName customer.firstName
    |> set #lastName customer.lastName
    |> set #reverseName (reverseNameOf customer.firstName customer.lastName)
    |> set #email customer.email
    |> set #phone customer.phone
    |> set #streetAddress customer.streetAddress
    |> set #postalCode customer.postalCode
    |> set #city customer.city
    |> createRecord

-- | A seed that changes every day, so each night's orders differ
seedFor :: UTCTime -> Word64
seedFor now = fromIntegral (toModifiedJulianDay (utctDay now))

-- * The orders

data CatalogItem = CatalogItem
    { productId :: Id Product
    , price :: Int
      -- ^ This season's price, in cents
    }

data DemoCustomer = DemoCustomer
    { firstName :: Text
    , lastName :: Text
    , email :: Text
    , phone :: Text
    , streetAddress :: Text
    , postalCode :: Text
    , city :: Text
    } deriving (Eq, Show)

data DemoLine = DemoLine
    { productId :: Id Product
    , quantity :: Int
    , unitPrice :: Int
    } deriving (Eq, Show)

data DemoOrder = DemoOrder
    { customer :: DemoCustomer
    , orderedAt :: UTCTime
    , invoicedAt, paidAt, deliveredAt, cancelledAt :: Maybe UTCTime
    , orderLines :: [DemoLine]
    } deriving (Eq, Show)

-- | Each product's price by season, this season first. Going back a year,
-- the price is 2–9% lower, or the same (about one year in four), rounded
-- to ten cents.
seasonPrices :: Word64 -> [CatalogItem] -> Map.Map (Id Product) [Int]
seasonPrices seed catalog = fst $ runGen (Map.fromList <$> mapM pricesOf catalog) (seed `xor` 0x5eed)
  where
    pricesOf item = do
        older <- go (seasons - 1) item.price
        pure (item.productId, item.price : older)
    go 0 _ = pure []
    go n newer = do
        unchanged <- genChance 0.25
        percent <- genInt 2 9
        let older
                | unchanged = newer
                | otherwise = min newer (roundToTen (fromIntegral newer / (1 + fromIntegral percent / 100)))
        (older :) <$> go (n - 1 :: Int) older
    roundToTen :: Double -> Int
    roundToTen cents = round (cents / 10) * 10

-- | The orders of every season, oldest first. A season is the six weeks
-- before this day of its year, so this season's newest orders are from
-- the last few days and still waiting to be handled. The business grows,
-- so later seasons have more orders, and regular customers come back.
demoOrders :: Word64 -> UTCTime -> [CatalogItem] -> [DemoOrder]
demoOrders _ _ [] = []
demoOrders seed now catalog = fst $ runGen generate seed
  where
    prices = seasonPrices seed catalog
    generate = do
        regulars <- replicateM 12 genCustomer
        concat <$> forM (reverse [0 .. seasons - 1]) (seasonOrders regulars)

    seasonOrders regulars age = do
        let end = if age == 0 then addUTCTime (negate 3600) now else yearsAgo age now
            start = addUTCTime (negate (42 * nominalDay)) end
        count <- genInt 0 6 |> fmap (+ (32 - 5 * age))
        returning <- filterM (const (genChance 0.6)) regulars
        newcomers <- replicateM (max 0 (count - length returning)) genCustomer
        orders <- forM (returning <> newcomers) \customer -> do
            orderedAt <- genTimeBetween start end
            orderLines <- genLines age
            states <- genStates orderedAt
            pure (states customer orderLines)
        pure (sortOn (.orderedAt) orders)

    genLines age = do
        count <- genWeighted [(5, 1), (4, 2), (2, 3), (1, 4)]
        items <- genDistinct count [(if item.productId `elem` oliveOils then 4 else 1, item) | item <- catalog]
        forM items \item -> do
            quantity <- genWeighted [(6, 1), (3, 2), (1, 3)]
            let unitPrice = fromMaybe item.price (Map.lookup item.productId prices >>= \ps -> ps `atMay` age)
            pure DemoLine { productId = item.productId, quantity, unitPrice }

    -- What has happened to the order by now: invoiced within two days,
    -- usually paid within ten days of that, delivered a few weeks after
    -- ordering. Some are cancelled, and an invoice still unpaid after a
    -- month is cancelled too.
    genStates orderedAt = do
        cancelledEarly <- genChance 0.04
        cancelDays <- genInt 1 3
        invoiceHours <- genInt 4 48
        pays <- genChance 0.92
        payDays <- genInt 1 10
        deliveryDays <- genInt 18 35
        let after seconds from = let t = addUTCTime seconds from in if t <= now then Just t else Nothing
            days n = fromIntegral (n :: Int) * nominalDay
            invoiced = if cancelledEarly then Nothing else after (fromIntegral (invoiceHours * 3600)) orderedAt
            paid = if pays then invoiced >>= after (days payDays) else Nothing
            delivered = paid >> after (days deliveryDays) orderedAt
            cancelled
                | cancelledEarly = after (days cancelDays) orderedAt
                | isNothing paid = invoiced >>= after (days 30)
                | otherwise = Nothing
        pure \customer orderLines -> DemoOrder
            { customer, orderedAt, orderLines
            , invoicedAt = invoiced, paidAt = paid, deliveredAt = delivered, cancelledAt = cancelled
            }

yearsAgo :: Int -> UTCTime -> UTCTime
yearsAgo n time = time { utctDay = addGregorianYearsClip (negate (fromIntegral n)) (utctDay time) }

atMay :: [a] -> Int -> Maybe a
atMay xs n = listToMaybe (drop n xs)

-- * Made-up customers

genCustomer :: Gen DemoCustomer
genCustomer = do
    first <- genPick firstNames
    lastName <- genPick lastNames
    (street, postcode, city) <- genPick places
    number <- genInt 1 60
    flat <- genChance 0.5
    stair <- genPick ["A", "B", "C"]
    door <- genInt 1 40
    phone <- genPhone
    let streetAddress = street <> " " <> tshow number
            <> (if flat then " " <> stair <> " " <> tshow door else "")
    pure DemoCustomer
        { firstName = first, lastName, email = emailFor (first <> " " <> lastName), phone
        , streetAddress, postalCode = postcode, city
        }

genPhone :: Gen Text
genPhone = do
    prefix <- genPick ["040", "041", "044", "045", "050"]
    digits <- replicateM 7 (genInt 0 9)
    let number = T.concat (map tshow digits)
    pure (prefix <> " " <> T.take 3 number <> " " <> T.drop 3 number)

-- | firstname.lastname@example.com, without accents or hyphens
emailFor :: Text -> Text
emailFor name = name
    |> toLower
    |> T.map (\case 'ä' -> 'a'; 'ö' -> 'o'; 'å' -> 'a'; c -> c)
    |> T.filter (/= '-')
    |> T.words
    |> T.intercalate "."
    |> (<> "@example.com")

-- | Subscribed to the newsletter without ordering
newsletterSubscribers :: [DemoCustomer]
newsletterSubscribers = fst $ runGen (replicateM 5 genCustomer) 0xfeed

firstNames :: [Text]
firstNames =
    [ "Maija", "Juhani", "Aino", "Pekka", "Elina", "Sanna", "Ville", "Tuomas", "Kaisa-Maria", "Olli"
    , "Leena", "Matti", "Hanna", "Antti", "Laura", "Mikko", "Riikka", "Jussi", "Eeva", "Timo"
    , "Satu", "Heikki", "Johanna", "Kari", "Minna", "Jari", "Tiina", "Petri", "Anu", "Markku"
    ]

lastNames :: [Text]
lastNames =
    [ "Virtanen", "Korhonen", "Mäkinen", "Laine", "Nieminen", "Heikkinen", "Hämäläinen", "Lehtonen"
    , "Järvinen", "Koskinen", "Salminen", "Rantanen", "Laaksonen", "Mäkelä", "Lehtinen", "Saarinen"
    , "Niemi", "Kinnunen", "Heinonen", "Tuominen", "Ahonen", "Lindholm", "Karjalainen", "Hiltunen"
    ]

places :: [(Text, Text, Text)]
places =
    [ ("Mannerheimintie", "00100", "Helsinki")
    , ("Fredrikinkatu", "00120", "Helsinki")
    , ("Hämeenkatu", "33100", "Tampere")
    , ("Puistokatu", "20100", "Turku")
    , ("Rantatie", "90100", "Oulu")
    , ("Kauppakatu", "40100", "Jyväskylä")
    , ("Asemakatu", "70100", "Kuopio")
    , ("Satamakatu", "15100", "Lahti")
    , ("Länsiväylä", "02160", "Espoo")
    , ("Torikatu", "28100", "Pori")
    , ("Kirkkokatu", "53100", "Lappeenranta")
    , ("Koulukatu", "65100", "Vaasa")
    ]

-- * A small seeded random generator (SplitMix64), so no extra dependency

newtype Gen a = Gen { runGen :: Word64 -> (a, Word64) }

instance Functor Gen where
    fmap f (Gen g) = Gen \s -> let (a, s') = g s in (f a, s')

instance Applicative Gen where
    pure a = Gen \s -> (a, s)
    Gen f <*> Gen g = Gen \s -> let (h, s1) = f s; (a, s2) = g s1 in (h a, s2)

instance Monad Gen where
    Gen g >>= k = Gen \s -> let (a, s1) = g s in runGen (k a) s1

genWord :: Gen Word64
genWord = Gen \s ->
    let s' = s + 0x9e3779b97f4a7c15
        z1 = (s' `xor` (s' `shiftR` 30)) * 0xbf58476d1ce4e5b9
        z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94d049bb133111eb
    in (z2 `xor` (z2 `shiftR` 31), s')

-- | A number from lo to hi, both included
genInt :: Int -> Int -> Gen Int
genInt lo hi = genWord |> fmap \w -> lo + fromIntegral (w `mod` fromIntegral (hi - lo + 1))

genChance :: Double -> Gen Bool
genChance p = genWord |> fmap \w -> fromIntegral (w `shiftR` 11) / 9007199254740992 < p

genPick :: [a] -> Gen a
genPick xs = genWeighted (map (1,) xs)

genWeighted :: [(Int, a)] -> Gen a
genWeighted choices = do
    n <- genInt 1 (sum (map fst choices))
    let go remaining ((weight, x) : rest)
            | remaining <= weight || null rest = x
            | otherwise = go (remaining - weight) rest
        go _ [] = error "genWeighted: no choices"
    pure (go n choices)

-- | Up to n different choices
genDistinct :: Int -> [(Int, a)] -> Gen [a]
genDistinct 0 _ = pure []
genDistinct _ [] = pure []
genDistinct n choices = do
    i <- genWeighted (zip (map fst choices) [0 :: Int ..])
    case List.splitAt i choices of
        (before, (_, chosen) : rest) -> (chosen :) <$> genDistinct (n - 1) (before <> rest)
        _ -> pure []

genTimeBetween :: UTCTime -> UTCTime -> Gen UTCTime
genTimeBetween start end = do
    let seconds = max 1 (floor (diffUTCTime end start) :: Int)
    offset <- genInt 0 seconds
    pure (addUTCTime (fromIntegral offset) start)
