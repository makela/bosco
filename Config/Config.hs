module Config where

import Control.Exception (evaluate)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import IHP.EnvVar
import IHP.Environment
import IHP.FrameworkConfig
import IHP.LoginSupport.Middleware
import IHP.Mail.Types (MailServer (Sendmail))
import IHP.Prelude
import IHP.View.CSSFramework

import Admin.Controller.Prelude
import Application.Localization (defaultLocale)
import Application.Settings

config :: ConfigBuilder
config = do
    option $ AuthMiddleware (authMiddleware @User)
    option tailwind

    -- The instance's settings, see nix/module.nix. Without any, the site
    -- is in Finnish and sends emails with the local sendmail.
    _ <- liftIO (evaluate defaultLocale) -- stops here if APP_LOCALE is wrong
    sendEmails <- envOrDefault "SEND_EMAILS" True
    option (EmailsEnabled sendEmails)
    demo <- envOrDefault "APP_DEMO" False
    either (error . cs) pure (checkDemoMode demo sendEmails)
    option (DemoMode demo)
    smtpHost <- envOrNothing "SMTP_HOST"
    case smtpHost of
        Nothing -> option Sendmail
        Just host -> do
            port <- envOrDefault "SMTP_PORT" 587
            user <- envOrNothing "SMTP_USER"
            passwordFile :: Maybe String <- envOrNothing "SMTP_PASSWORD_FILE"
            password <- liftIO (mapM (fmap T.strip . TIO.readFile) passwordFile)
            encryption <- envOrDefault "SMTP_ENCRYPTION" "starttls"
            either (error . cs) option (smtpServer host port user password encryption)
