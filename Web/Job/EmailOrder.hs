module Web.Job.EmailOrder where
import Web.Controller.Orders (fetchShowOrderContext)
import Web.Controller.Prelude
import Web.Mail.Orders.Order

instance Job EmailOrderJob where
    perform EmailOrderJob { .. } = do
        (order, totalSum, orderedProductsByProducer, producers) <-
            fetchShowOrderContext orderId
        paymentInstruction <- query @PaymentInstruction |> orderByDesc #publishedAt |> fetchOneOrNothing
        sendMail $ OrderMail { .. }
