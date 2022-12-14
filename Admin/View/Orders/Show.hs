module Admin.View.Orders.Show where
import Admin.View.Prelude
import Admin.View.Orders.Index (formatUTCTime)
import Web.View.Orders.New (formatMoney)
import Web.View.Orders.Show (renderCustomer, OrderedProductsByProducer, renderProducer, renderTotalSum)

data ShowView = ShowView
    { order :: Include "customerId" Order
    , producers :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , totalSum :: Int
    , user :: User
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
        {markPaid}
        {markDelivered}
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
