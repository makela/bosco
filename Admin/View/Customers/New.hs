module Admin.View.Customers.New where
import Admin.View.Prelude

data NewView = NewView { customer :: Customer }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        {renderForm customer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Customers" CustomersAction
                , breadcrumbText "New"
                ]

renderForm :: Customer -> Html
renderForm customer = formFor customer [hsx|
    {(textField #firstName) { required = True, autofocus = True }}
    {textField #lastName}
    {(textField #email) { required = True }}
    {(textField #phone) { required = True }}
    {textField #streetAddress}
    {textField #postalCode}
    {textField #city}
    {submitButton}

|]
