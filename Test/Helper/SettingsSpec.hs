module Test.Helper.SettingsSpec where

import Data.Either (isLeft)

import IHP.Mail.Types (MailServer (..), SMTPEncryption (..))
import IHP.Prelude
import Test.Hspec

import Application.Localization (Locale (..), parseLocale)
import Application.Settings (smtpServer)

tests :: Spec
tests = describe "Instance settings" do
    describe "parseLocale (APP_LOCALE)" do
        it "reads the language codes" do
            map parseLocale ["fi", "en", "fr"] `shouldBe` [Right FI, Right EN, Right FR]

        it "uses Finnish when unset" do
            parseLocale "" `shouldBe` Right FI

        it "rejects other values and lists the valid ones" do
            parseLocale "FR" `shouldBe` Left "APP_LOCALE should be one of fi, en, fr, got FR"
            parseLocale "sv" `shouldSatisfy` isLeft

    describe "smtpServer" do
        it "uses STARTTLS with a user and password" do
            describe' (smtpServer "smtp.example.com" 587 (Just "shop") (Just "secret") "starttls")
                `shouldBe` Right "smtp.example.com:587 STARTTLS as shop"

        it "can use TLS, or no login at all" do
            describe' (smtpServer "smtp.example.com" 465 (Just "shop") (Just "secret") "TLS")
                `shouldBe` Right "smtp.example.com:465 TLS as shop"
            describe' (smtpServer "localhost" 25 Nothing Nothing "none")
                `shouldBe` Right "localhost:25 none without login"

        it "refuses half a login" do
            describe' (smtpServer "smtp.example.com" 587 (Just "shop") Nothing "starttls") `shouldSatisfy` isLeft
            describe' (smtpServer "smtp.example.com" 587 Nothing (Just "secret") "starttls") `shouldSatisfy` isLeft

        it "refuses to send a password unencrypted" do
            describe' (smtpServer "smtp.example.com" 25 (Just "shop") (Just "secret") "none") `shouldSatisfy` isLeft

        it "refuses unknown encryption and an empty host" do
            describe' (smtpServer "smtp.example.com" 587 Nothing Nothing "ssl") `shouldSatisfy` isLeft
            describe' (smtpServer " " 587 Nothing Nothing "starttls") `shouldSatisfy` isLeft
  where
    -- MailServer has no Show or Eq, so compare a description of it
    describe' :: Either Text MailServer -> Either Text Text
    describe' = fmap \case
        SMTP { host, port, credentials, encryption } ->
            cs host <> ":" <> tshow (fromIntegral port :: Int) <> " "
                <> (case encryption of STARTTLS -> "STARTTLS"; TLS -> "TLS"; Unencrypted -> "none")
                <> maybe " without login" (\(user, _) -> " as " <> cs user) credentials
        _ -> "not SMTP"
