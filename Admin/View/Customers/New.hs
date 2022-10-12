module Admin.View.Customers.New where
import Admin.View.Prelude

data NewView = NewView { customer :: Customer }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        <h1>New Customer</h1>
        {renderForm customer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Customers" CustomersAction
                , breadcrumbText "New Customer"
                ]

renderForm :: Customer -> Html
renderForm customer = formFor customer [hsx|
    {(textField #name) { required = True, autofocus = True }}
    {(textField #email) { required = True }}
    {(textField #phone) { required = True }}
    {(textField #address) { required = True }}
    {submitButton}

|]
