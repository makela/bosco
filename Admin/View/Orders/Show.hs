module Admin.View.Orders.Show where
import Admin.View.Prelude
import Web.View.Orders.New (formatMoney)
import Web.View.Orders.Show (renderCustomer, OrderedProductsByProducer, renderProducer)

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
            <tr class="font-bold">
                <td>Yhteensä</td>
                <td></td>
                <td></td>
                <td></td>
                <td></td>
                <td class="last">{formatMoney totalSum}</td>
            </tr>
        </tbody>
        </table>

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
                    , breadcrumbLink "Cancel" (CancelOrderAction order.id)
                    ]
                (_, _) -> baseBreadcrumbs
            breadcrumb = renderBreadcrumb breadcrumbs
