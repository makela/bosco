module Admin.View.Orders.Show where
import Admin.View.Prelude

data ShowView = ShowView { order :: Include "customerId" Order }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <h1>{order.customerId.name}</h1>
        <p>{order.customerId.email}</p>
        <p>{order.customerId.phone}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                            [ breadcrumbLink "Orders" OrdersAction
                            , breadcrumbText "Show Order"
                            ]
