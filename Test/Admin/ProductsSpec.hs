module Test.Admin.ProductsSpec where

import qualified Data.Text as T
import Network.HTTP.Types (status200)

import IHP.ControllerPrelude
import IHP.Hspec (responseStatusShouldBe, withIHPApp)
import IHP.Test.Mocking
import Test.Hspec

import Admin.Controller.Products ()
import Admin.FrontController ()
import Admin.Types
import Config
import Generated.Types

import Test.Admin.Users (createAdmin)

tests :: Spec
tests = aroundAll (withIHPApp AdminApplication config) do
    describe "Admin ProductsAction" do
        it "lists all products grouped by producer, even more than a page's worth" $ withContext do
            admin <- createAdmin
            -- 60 products: by name alone, the "Aaa" producer's ones sort last
            aaa <- createProducer "Aaa tila"
            zzz <- createProducer "Zzz tila"
            forM_ [1 .. 30 :: Int] \i -> do
                createProduct aaa ("Zz " <> padded i)
                createProduct zzz ("Aa " <> padded i)
            response <- withUser admin $ callAction ProductsAction
            response `responseStatusShouldBe` status200
            body :: Text <- cs <$> responseBody response
            let position name = T.length (fst (T.breakOn name body))
                aaaNames = map (\i -> "Zz " <> padded i) [1 .. 30]
                zzzNames = map (\i -> "Aa " <> padded i) [1 .. 30]
            forM_ (aaaNames <> zzzNames) \name -> body `shouldSatisfy` (name `T.isInfixOf`)
            -- Every "Aaa tila" product comes before every "Zzz tila" product
            maximum (map position aaaNames) `shouldSatisfy` (< minimum (map position zzzNames))
  where
    padded i = if i < 10 then "0" <> tshow i else tshow i
    createProducer name = newRecord @Producer
        |> set #name name
        |> set #subject ""
        |> set #description ""
        |> createRecord
    createProduct producer name = newRecord @Product
        |> set #producerId producer.id
        |> set #name name
        |> set #description ""
        |> set #package "1 l"
        |> set #price 1000
        |> createRecord
        |> fmap (const ())
