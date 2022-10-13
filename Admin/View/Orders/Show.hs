module Admin.View.Orders.Show where
import Admin.View.Prelude
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
        {paidOrCancelled}

    |]
        where
            baseBreadcrumbs =
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Orders" OrdersAction
                , breadcrumbText (timeAgo order.orderedAt)
                ]
            breadcrumbs = case (order.cancelledAt, order.paidAt) of
                (Nothing, Nothing) -> baseBreadcrumbs ++
                    [ breadcrumbLink "Mark Paid" (MarkPaidOrderAction order.id)
                    , breadcrumbLink [hsx|<a href={CancelOrderAction order.id} class="back-button">Cancel</a>|] (CancelOrderAction order.id)
                    ]
                (_, _) -> baseBreadcrumbs
            breadcrumb = renderBreadcrumb breadcrumbs
            paidOrCancelled = case (order.paidAt, order.cancelledAt) of
                (Just paidAt, _) -> [hsx|<p class="font-bold">Paid {timeAgo paidAt}</p>|]
                (_ , Just cancelledAt) -> [hsx|<p class="font-bold">Cancelled {timeAgo cancelledAt}</p>|]
                (_, _) -> pure ()
