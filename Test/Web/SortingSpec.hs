module Test.Web.SortingSpec where

import qualified Data.Map as Map

import IHP.ModelSupport (newRecord, textToId)
import IHP.Prelude
import Test.Hspec

import Generated.Types
import Web.Controller.Orders (groupProducts, sortProducers)

tests :: Spec
tests = describe "Web.Controller.Orders sorting" do
    describe "sortProducers" do
        it "puts Bosco Falconeria first, then the rest A to Z" do
            let names = ["Stramondo", "bonomo & Giglio", "Valdibella", "Bosco Falconeria", "Lorcam", "Quetzal"]
            map (.name) (sortProducers (map producer names))
                `shouldBe` ["Bosco Falconeria", "bonomo & Giglio", "Lorcam", "Quetzal", "Stramondo", "Valdibella"]

    describe "groupProducts" do
        it "groups products by producer" do
            let grouped = groupProducts [product farm "A" Nothing 100, product other "B" Nothing 100]
            Map.map (map (.name)) grouped `shouldBe` Map.fromList [(farm, ["A"]), (other, ["B"])]

        it "orders by the ordering field, empty last, then by name and price" do
            let products =
                    [ product farm "Valkoviinietikkaa" Nothing 650
                    , product farm "oliiviöljyä" Nothing 5100
                    , product farm "Zibibbo" (Just 2) 980
                    , product farm "Valkoviinietikkaa" Nothing 440
                    , product farm "Basilika" Nothing 550
                    , product farm "Mantelit" (Just 1) 1010
                    ]
                described p = p.name <> " " <> tshow p.price
            map described (fromMaybe [] (Map.lookup farm (groupProducts products)))
                `shouldBe`
                    [ "Mantelit 1010", "Zibibbo 980"
                    , "Basilika 550", "oliiviöljyä 5100", "Valkoviinietikkaa 440", "Valkoviinietikkaa 650" ]

        it "does not depend on the order it is given" do
            let products = [ product farm (cs [c]) Nothing 100 | c <- "dbeac" ]
            map (.name) (fromMaybe [] (Map.lookup farm (groupProducts products)))
                `shouldBe` ["a", "b", "c", "d", "e"]
  where
    farm = textToId ("00000000-0000-0000-0000-000000000001" :: Text)
    other = textToId ("00000000-0000-0000-0000-000000000002" :: Text)
    producer name = newRecord @Producer |> set #name name
    product producerId name ordering price = newRecord @Product
        |> set #producerId producerId
        |> set #name name
        |> set #ordering ordering
        |> set #price price
