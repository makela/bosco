module Admin.View.Customers.Show where
import Admin.View.Prelude

data ShowView = ShowView { customer :: Customer }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <h1>Show Customer</h1>
        <p>{customer}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                            [ breadcrumbLink "Customers" CustomersAction
                            , breadcrumbText "Show Customer"
                            ]