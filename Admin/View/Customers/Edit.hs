module Admin.View.Customers.Edit where
import Admin.View.Prelude

data EditView = EditView { customer :: Customer }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        <h1>Edit Customer</h1>
        {renderForm customer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Customers" CustomersAction
                , breadcrumbText "Edit Customer"
                ]

renderForm :: Customer -> Html
renderForm customer = formFor customer [hsx|
    {(textField #name) { required = True, autofocus = True }}
    {(textField #email) { required = True }}
    {(textField #phone) { required = True }}
    {(textField #address) { required = True }}
    {submitButton}

|]
