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
        {markDelivered}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Orders" OrdersAction
                , breadcrumbText [hsx|{formatUTCTime order.orderedAt}|]
                ]
            markDelivered = case order.deliveredAt of
                Just _ -> pure ()
                Nothing -> [hsx|
                    <form method="POST" action={UpdateDeliverOrderAction order.id}>
                        <input type="submit" value="Mark as delivered" />
                    </form>
                |]
