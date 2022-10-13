module Admin.View.Customers.Show where
import Admin.View.Prelude

data ShowView = ShowView { customer :: Customer }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <p>{customer}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Customers" CustomersAction
                , breadcrumbText [hsx|{customer.name}|]
                , breadcrumbLink "Edit" (EditCustomerAction customer.id)
                ]
