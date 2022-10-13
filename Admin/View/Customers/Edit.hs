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
                , breadcrumbLink [hsx|{customer.name}|] (ShowCustomerAction customer.id)
                , breadcrumbText "Edit"
                , breadcrumbLink [hsx|<a href={DeleteCustomerAction customer.id} class="js-delete back-button">Delete</a>|] (DeleteCustomerAction customer.id)
                ]

renderForm :: Customer -> Html
renderForm customer = formFor customer [hsx|
    {(textField #name) { required = True, autofocus = True }}
    {(textField #email) { required = True }}
    {(textField #phone) { required = True }}
    {(textField #address) { required = True }}
    {submitButton}

|]
