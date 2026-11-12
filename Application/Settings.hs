-- | Settings that differ between instances of the site, read from the
-- environment in Config.hs. The NixOS module (nix/module.nix) sets them.
module Application.Settings
    ( EmailsEnabled (..)
    , DemoMode (..)
    , checkDemoMode
    , smtpServer
    , MailAddresses (..)
    , parseAddress
    ) where

import qualified Data.Text as T

import IHP.Mail.Types (MailServer (..), SMTPEncryption (..))
import IHP.MailPrelude (Address (..))
import IHP.Prelude

-- | Whether this instance sends emails (SEND_EMAILS, on by default). A
-- staging instance turns it off, and its email jobs only log the email.
newtype EmailsEnabled = EmailsEnabled Bool

-- | Whether this instance is a public demo (APP_DEMO, off by default). A
-- demo marks every page as one, keeps search engines out and tells
-- customers not to pay its invoices.
newtype DemoMode = DemoMode Bool

-- | Who the order emails are from (MAIL_FROM), and where replies to them
-- go (MAIL_REPLY_TO, none when unset)
data MailAddresses = MailAddresses
    { mailFrom :: Address
    , mailReplyTo :: Maybe Address
    }

-- | An address as "someone@example.com" or "Some Name <someone@example.com>"
parseAddress :: Text -> Address
parseAddress text = case T.breakOnEnd "<" (T.strip text) of
    (before, after) | not (T.null before), Just email <- T.stripSuffix ">" after ->
        let name = T.strip (T.dropEnd 1 before) |> T.dropAround (== '"')
        in Address { addressName = if T.null name then Nothing else Just name, addressEmail = T.strip email }
    _ -> Address { addressName = Nothing, addressEmail = T.strip text }

-- | A demo must not send emails: anyone could make it email any address,
-- and its invoices must not reach anyone's inbox.
checkDemoMode :: Bool -> Bool -> Either Text ()
checkDemoMode demo sendEmails
    | demo && sendEmails = Left "APP_DEMO needs SEND_EMAILS=0: a demo must not send emails"
    | otherwise = Right ()

-- | The SMTP server from SMTP_HOST, SMTP_PORT, SMTP_USER, the password in
-- SMTP_PASSWORD_FILE and SMTP_ENCRYPTION (starttls, tls or none).
smtpServer :: Text -> Int -> Maybe Text -> Maybe Text -> Text -> Either Text MailServer
smtpServer host port user password encryptionName = do
    encryption <- case toLower encryptionName of
        "starttls" -> Right STARTTLS
        "tls" -> Right TLS
        "none" -> Right Unencrypted
        other -> Left ("SMTP_ENCRYPTION should be starttls, tls or none, got " <> other)
    credentials <- case (user, password) of
        (Just user, Just password) -> Right (Just (cs user, cs password))
        (Nothing, Nothing) -> Right Nothing
        _ -> Left "Set both SMTP_USER and SMTP_PASSWORD_FILE, or neither"
    case (encryption, credentials) of
        (Unencrypted, Just _) -> Left "Refusing to send the SMTP password unencrypted; use starttls or tls"
        _ -> pure ()
    when (T.null (T.strip host)) (Left "SMTP_HOST is empty")
    pure SMTP { host = cs host, port = fromIntegral port, credentials, encryption }
