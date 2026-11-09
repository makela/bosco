module Admin.View.Orders.Show where
import IHP.Job.Types (JobStatus (..))

import Admin.View.Orders.Index (formatUTCTime)
import Admin.View.Prelude
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
                , breadcrumbText [hsx|{formatUTCTime order.orderedAt}|]
                ]
            markPaid = case (user.isAdmin, order.paidAt) of
                (True, Nothing) -> [hsx|
                    <form method="POST" action={UpdateMarkPaidOrderAction order.id}>
                        <input type="submit" class="btn-small" value="Mark as paid" />
                    </form>
                |]
                (_, _) -> pure ()
            markDelivered = case order.deliveredAt of
                Just _ -> pure ()
                Nothing -> [hsx|
                    <form method="POST" action={UpdateDeliverOrderAction order.id}>
                        <input type="submit" class="btn-small" value="Mark as delivered" />
                    </form>
                |]
            markInvoiced = case order.invoicedAt of
                Just _ -> pure ()
                Nothing -> [hsx|
                    <form method="POST" action={UpdateInvoiceOrderAction order.id}>
                        <input type="submit" class="btn-small" value="Mark as invoiced" />
                    </form>
                |]
            sendInvoice = when user.isAdmin [hsx|
                <form method="POST" action={UpdateSendInvoiceOrderAction order.id}>
                    <input type="submit" class="btn-small" value="Send invoice" />
                </form>
            |]
            cancelOrder = case (user.isAdmin, order.paidAt) of
                (True, Nothing) -> [hsx|
                    <a href={DeleteCancelOrderAction order.id} class="js-delete btn-small danger">Cancel order</a>
                |]
                (_, _) -> pure ()
            cancelledOrControls = case order.cancelledAt of
                Just x -> [hsx|<p>Cancelled {formatUTCTime x}</p>|]
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
renderEmailJob job = [hsx|<li>{describe job.status}</li>|]
    where
        time :: UTCTime -> Text
        time = cs . formatUTCTime
        describe :: JobStatus -> Text
        describe = \case
            JobStatusSucceeded -> "Emailed " <> time job.updatedAt
            JobStatusFailed -> "Failed " <> time job.updatedAt <> ": " <> fromMaybe "" job.lastError
            JobStatusTimedOut -> "Timed out " <> time job.updatedAt
            JobStatusRetry -> "Failed " <> time job.updatedAt <> ", trying again: " <> fromMaybe "" job.lastError
            JobStatusRunning -> "Sending, queued " <> time job.createdAt
            JobStatusNotStarted -> "Queued " <> time job.createdAt
