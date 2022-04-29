module Web.View.Orders.Show where
import Web.View.Prelude

data ShowView = ShowView { order :: Order }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <h1>Show Order</h1>
        <p>{order}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                            [ breadcrumbLink "Orders" OrdersAction
                            , breadcrumbText "Show Order"
                            ]