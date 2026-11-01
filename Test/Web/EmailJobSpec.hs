module Test.Web.EmailJobSpec where

import qualified Control.Exception as Exception
import qualified System.Environment as Environment

import IHP.ControllerPrelude
import IHP.Hspec (withIHPApp)
import qualified Data.TMap as TMap
import IHP.Mail (MailServer (..))
import IHP.Test.Mocking
import Test.Hspec

import Config
import Generated.Types
import Web.FrontController ()
import Web.Job.EmailOrder ()
import Web.Types

tests :: Spec
tests = do
    describe "Mail server" do
        aroundAll (withIHPApp WebApplication config) do
            it "is configured, so email jobs don't fail with 'No mail server configured'" $ withContext do
                -- The lookup IHP's sendMail does; without SMTP_HOST, the
                -- local sendmail as before
                let server = TMap.lookup @MailServer ?mocking.frameworkConfig.appConfig
                (case server of Just Sendmail -> True; _ -> False) `shouldBe` True

    describe "Email job with SEND_EMAILS=0 (a staging instance)" do
        aroundAll withEmailsOff do
            it "finishes without sending" $ withContext do
                customer <- newRecord @Customer
                    |> set #name "Staging Customer"
                    |> set #email "staging@example.com"
                    |> set #phone "0401234567"
                    |> set #address "Testikatu 1"
                    |> createRecord
                order <- newRecord @Order |> set #customerId customer.id |> createRecord
                job <- newRecord @EmailOrderJob |> set #orderId order.id |> createRecord
                -- Sending would need a mail server, which the tests don't have
                callJob job
  where
    withEmailsOff action = Exception.bracket_
        (Environment.setEnv "SEND_EMAILS" "0")
        (Environment.unsetEnv "SEND_EMAILS")
        (withIHPApp WebApplication config action)
