module Admin.View.Orders.Index where
import Admin.View.Prelude

data IndexView = IndexView
    { orders :: [Include "customerId" Order]
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Ordered At</th>
                        <th>Customer</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach orders renderOrder}</tbody>
            </table>
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText "Orders"
                ]

renderOrder :: Include "customerId" Order -> Html
renderOrder order = [hsx|
    <tr>
        <td><a href={ShowOrderAction order.id}>{order.orderedAt}</a></td>
        <td>{order.customerId.name}</td>
        <td></td>
    </tr>
|]
