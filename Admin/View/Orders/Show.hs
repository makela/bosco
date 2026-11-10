module Admin.View.Orders.Show where
import IHP.Job.Types (JobStatus (..))

import Admin.View.Prelude
import Application.Permission (Permission (..), can)
import Web.View.Orders.New (formatMoney)
import Web.View.Orders.Show (OrderedProductsByProducer, renderCustomer,
                             renderProducer, renderTotalSum)

data ShowView = ShowView
    { order                     :: Include "customerId" Order
    , producers                 :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , totalSum                  :: Int
    , user                      :: User
    , emailJobs                 :: [EmailOrderJob]
      -- ^ Every time the invoice was emailed, or is to be, oldest first
    , emailsEnabled             :: Bool
    }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        {renderCustomer order.customerId}
        <table>
        <tbody>
            {forEach producers (renderProducer orderedProductsByProducer)}
            {renderTotalSum totalSum}
        </tbody>
        </table>
        {cancelledOrControls}
        {renderEmailHistory emailsEnabled emailJobs}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Orders" OrdersAction
                , breadcrumbText (dateTime order.orderedAt)
                ]
            markPaid = case (can user ManageOrders, order.paidAt) of
                (True, Nothing) -> [hsx|
                    <form method="POST" action={UpdateMarkPaidOrderAction order.id}>
                        <input type="submit" class="btn-small" value="Mark as paid" />
                    </form>
                |]
                (_, _) -> pure ()
            markDelivered = case (can user MarkDelivered, order.deliveredAt) of
                (True, Nothing) -> [hsx|
                    <form method="POST" action={UpdateDeliverOrderAction order.id}>
                        <input type="submit" class="btn-small" value="Mark as delivered" />
                    </form>
                |]
                (_, _) -> pure ()
            markInvoiced = case (can user ManageOrders, order.invoicedAt) of
                (True, Nothing) -> [hsx|
                    <form method="POST" action={UpdateInvoiceOrderAction order.id}>
                        <input type="submit" class="btn-small" value="Mark as invoiced" />
                    </form>
                |]
                (_, _) -> pure ()
            sendInvoice = when (can user ManageOrders) [hsx|
                <form method="POST" action={UpdateSendInvoiceOrderAction order.id}>
                    <input type="submit" class="btn-small" value="Send invoice" />
                </form>
            |]
            cancelOrder = case (can user ManageOrders, order.paidAt) of
                (True, Nothing) -> [hsx|
                    <a href={DeleteCancelOrderAction order.id} class="js-delete btn-small danger">Cancel order</a>
                |]
                (_, _) -> pure ()
            cancelledOrControls = case order.cancelledAt of
                Just x -> [hsx|<p>Cancelled {dateTime x}</p>|]
                Nothing -> [hsx|
                    <div class="order-steps">
                        {sendInvoice}
                        {markInvoiced}
                        {markPaid}
                        {markDelivered}
                        {cancelOrder}
                    </div>
                |]

-- | When the invoice was emailed to the customer: on ordering, and whenever
-- an admin sent it again
renderEmailHistory :: Bool -> [EmailOrderJob] -> Html
renderEmailHistory _ [] = [hsx|<p id="email-history">The invoice hasn't been emailed.</p>|]
renderEmailHistory emailsEnabled jobs = [hsx|
    <div id="email-history">
        <h2>Invoice emails</h2>
        {emailsOff}
        <ul>{forEach jobs renderEmailJob}</ul>
    </div>
|]
    where
        emailsOff = unless emailsEnabled [hsx|
            <p>Emails are off for this instance, so none of these was actually sent.</p>
        |]

renderEmailJob :: EmailOrderJob -> Html
renderEmailJob job = [hsx|<li>{label} {dateTime at}{detail}</li>|]
    where
        lastError = fromMaybe "" job.lastError
        (label, at, detail) :: (Text, UTCTime, Text) = case job.status of
            JobStatusSucceeded -> ("Emailed", job.updatedAt, "")
            JobStatusFailed -> ("Failed", job.updatedAt, ": " <> lastError)
            JobStatusTimedOut -> ("Timed out", job.updatedAt, "")
            JobStatusRetry -> ("Failed", job.updatedAt, ", trying again: " <> lastError)
            JobStatusRunning -> ("Sending, queued", job.createdAt, "")
            JobStatusNotStarted -> ("Queued", job.createdAt, "")
