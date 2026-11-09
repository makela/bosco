module Admin.View.Customers.Show where
import Admin.View.Prelude

data ShowView = ShowView { customer :: Customer }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        {when (customer.billingName /= "") billingName}
        <p>{customer.email}</p>
        <p>{customer.phone}</p>
        {renderAddressLines customer}

    |]
        where
            billingName = [hsx|<p>{customer.billingName}</p>|]
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Customers" CustomersAction
                , breadcrumbText [hsx|{fullName customer}|]
                , breadcrumbLink "Edit" (EditCustomerAction customer.id)
                ]
