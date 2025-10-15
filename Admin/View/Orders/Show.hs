module Admin.View.Orders.Show where
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
                        <input type="submit" value="Mark as paid" />
                    </form>
                |]
                (_, _) -> pure ()
            markDelivered = case order.deliveredAt of
                Just _ -> pure ()
                Nothing -> [hsx|
                    <form method="POST" action={UpdateDeliverOrderAction order.id}>
                        <input type="submit" value="Mark as delivered" />
                    </form>
                |]
            markInvoiced = case order.invoicedAt of
                Just _ -> pure ()
                Nothing -> [hsx|
                    <form method="POST" action={UpdateInvoiceOrderAction order.id}>
                        <input type="submit" value="Mark as invoiced" />
                    </form>
                |]
            cancelOrder = case (user.isAdmin, order.paidAt) of
                (True, Nothing) -> [hsx|
                    <p><a href={DeleteCancelOrderAction order.id} class="js-delete back-button">Cancel order</a></p>
                |]
                (_, _) -> pure ()
            cancelledOrControls = case order.cancelledAt of
                Just x -> [hsx|<p>Cancelled {formatUTCTime x}</p>|]
                Nothing -> [hsx|
                    {markInvoiced}
                    {markPaid}
                    {markDelivered}
                    {cancelOrder}
                |]
