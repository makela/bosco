module Web.Job.EmailOrder where

import IHP.Mail

import Application.Settings (EmailsEnabled (..))
import Web.Controller.Orders (fetchShowOrderContext)
import Web.Controller.Prelude
import Web.Mail.Orders.Order

instance Job EmailOrderJob where
    perform EmailOrderJob { .. } = do
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
        paymentInstruction <- query @PaymentInstruction |> orderByDesc #publishedAt |> fetchOneOrNothing
        let EmailsEnabled enabled = getAppConfig @EmailsEnabled
        if enabled
            then sendMail OrderMail { .. }
            else putStrLn ("Emails are off for this instance: not sending order "
                <> tshow orderId <> " to " <> order.customerId.email)
