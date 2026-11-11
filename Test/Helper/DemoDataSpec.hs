module Test.Helper.DemoDataSpec where

import qualified Data.Map as Map
import Data.Time.Calendar (toGregorian)
import Data.Time.Clock (addUTCTime, nominalDay)

import IHP.ModelSupport (textToId)
import IHP.Prelude
import Test.Hspec

import Application.DemoData
import Generated.Types

tests :: Spec
tests = describe "Application.DemoData" do
    let now = UTCTime (fromGregorian 2026 11 8) 43200
        oil = CatalogItem { productId = textToId ("61db0ec5-698a-4b48-b19b-995d41472bb1" :: Text), price = 5100 }
        chocolate = CatalogItem { productId = textToId ("c5292736-21d4-4846-a192-2447ef3fdf9f" :: Text), price = 410 }
        catalog = [oil, chocolate]
        orders = demoOrders 42 now catalog
        yearOf order = let (year, _, _) = toGregorian (utctDay order.orderedAt) in year

    describe "fixtureInserts" do
        it "keeps only the INSERTs, with their line breaks" do
            fixtureInserts (unlines
                [ "SET client_encoding = 'UTF8';"
                , "ALTER TABLE public.producers DISABLE TRIGGER ALL;"
                , "INSERT INTO public.producers (id, name) VALUES ('1', 'One');"
                , "INSERT INTO public.producers (id, description) VALUES ('2', 'First line"
                , "second line (with parentheses);"
                , "<http://example.com>');"
                , "ALTER TABLE public.producers ENABLE TRIGGER ALL;"
                ])
                `shouldBe`
                [ "INSERT INTO public.producers (id, name) VALUES ('1', 'One');"
                , "INSERT INTO public.producers (id, description) VALUES ('2', 'First line\nsecond line (with parentheses);\n<http://example.com>');"
                ]

    describe "seasonPrices" do
        let prices = seasonPrices 42 catalog
        it "has this season's price first and never goes up going back" do
            forM_ catalog \item -> do
                let itemPrices = Map.findWithDefault [] item.productId prices
                length itemPrices `shouldBe` seasons
                take 1 itemPrices `shouldBe` [item.price]
                and (zipWith (>=) itemPrices (drop 1 itemPrices)) `shouldBe` True

        it "has older prices rounded to ten cents and lower in the end" do
            forM_ catalog \item -> do
                let older = drop 1 (Map.findWithDefault [] item.productId prices)
                all (\p -> p `mod` 10 == 0) older `shouldBe` True
            -- Over many products, some prices went up
            let many = [chocolate { productId = textToId ("00000000-0000-0000-0000-0000000000" <> (if i < 10 then "0" else "") <> tshow i), price = 1000 } | i <- [1 .. 20 :: Int]]
                manyPrices = seasonPrices 7 many
            any (\ps -> lastDef 0 ps < 1000) (Map.elems manyPrices) `shouldBe` True

    describe "demoOrders" do
        it "gives the same orders for the same seed, and others for another" do
            demoOrders 42 now catalog `shouldBe` orders
            demoOrders 43 now catalog `shouldNotBe` orders

        it "has orders in each of the last seasons, more in later ones" do
            let byYear = map (\y -> length (filter ((== y) . yearOf) orders)) [2023 .. 2026]
            all (> 10) byYear `shouldBe` True
            sum (take 2 byYear) `shouldSatisfy` (< sum (drop 2 byYear))

        it "has events in order, none in the future" do
            forM_ orders \order -> do
                let times = order.orderedAt : catMaybes [order.invoicedAt, order.paidAt, order.deliveredAt, order.cancelledAt]
                all (<= now) times `shouldBe` True
                all (>= order.orderedAt) times `shouldBe` True
                when (isJust order.paidAt) (order.invoicedAt `shouldSatisfy` isJust)
                when (isJust order.deliveredAt) (order.paidAt `shouldSatisfy` isJust)

        it "has older seasons handled and this season's newest orders waiting" do
            let old = filter ((< 2026) . yearOf) orders
                recent = filter (\o -> o.orderedAt > addUTCTime (negate (7 * nominalDay)) now) orders
            all (\o -> isJust o.deliveredAt || isJust o.cancelledAt) old `shouldBe` True
            recent `shouldSatisfy` (not . null)
            all (\o -> isNothing o.deliveredAt) recent `shouldBe` True
            any (\o -> isNothing o.paidAt && isNothing o.cancelledAt) recent `shouldBe` True

        it "has olive oil ordered more than the other products" do
            let others = [CatalogItem { productId = textToId ("00000000-0000-0000-0000-00000000000" <> tshow i), price = 410 } | i <- [1 .. 6 :: Int]]
                many = demoOrders 42 now (oil : others)
                linesOf :: CatalogItem -> Int
                linesOf item = length [() | order <- many, line <- order.orderLines, line.productId == item.productId]
            -- Without the weight it would be about as many as each other product
            (2 * linesOf oil) `shouldSatisfy` (> 3 * maximum (map linesOf others))

        it "charges each season's price" do
            let prices = seasonPrices 42 catalog
            forM_ orders \order -> forM_ order.orderLines \line -> do
                let age = 2026 - yearOf order
                Just line.unitPrice `shouldBe` (Map.lookup line.productId prices >>= listToMaybe . drop (fromInteger age))
  where
    lastDef d xs = fromMaybe d (last xs)
