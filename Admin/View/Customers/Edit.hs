module Admin.View.Customers.Edit where
import Admin.View.Prelude

data EditView = EditView { customer :: Customer }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {renderForm customer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Customers" CustomersAction
                , breadcrumbLink [hsx|{fullName customer}|] (ShowCustomerAction customer.id)
                , breadcrumbText "Edit"
                , breadcrumbLink [hsx|<a href={DeleteCustomerAction customer.id} class="js-delete back-button">Delete</a>|] (DeleteCustomerAction customer.id)
                ]

renderForm :: Customer -> Html
renderForm customer = formFor customer [hsx|
    {(textField #firstName) { required = True, autofocus = True }}
    {textField #lastName}
    {(textField #billingName) { fieldLabel = "Name on the invoice / Company name" }}
    {(textField #email) { required = True }}
    {(textField #phone) { required = True }}
    {textField #streetAddress}
    {textField #postalCode}
    {textField #city}
    {submitButton}

|]
