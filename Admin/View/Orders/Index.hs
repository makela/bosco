module Admin.View.Orders.Index where
import Admin.View.Prelude

data IndexView = IndexView
    { orders :: [Include "customerId" Order]
    , pagination :: Pagination
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Order</th>
                        <th>Ordered At</th>
                        <th>Paid At</th>
                        <th>Cancelled At</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach orders renderOrder}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Orders" OrdersAction
                ]

renderOrder :: Include "customerId" Order -> Html
renderOrder order = [hsx|
    <tr>
        <td>{order.customerId.name}</td>
        <td>{timeAgo order.orderedAt}</td>
        <td>{fmap timeAgo order.paidAt}</td>
        <td>{fmap timeAgo order.cancelledAt}</td>
        <td><a href={ShowOrderAction order.id}>Show</a></td>
    </tr>
|]
