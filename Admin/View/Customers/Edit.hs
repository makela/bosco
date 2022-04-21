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
    {(textField #name)}
    {(textField #email)}
    {(textField #phone)}
    {submitButton}

|]