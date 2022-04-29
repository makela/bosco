module Web.View.Orders.Edit where
import Web.View.Prelude

data EditView = EditView { order :: Order }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        <h1>Edit Order</h1>
        {renderForm order}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Orders" OrdersAction
                , breadcrumbText "Edit Order"
                ]

renderForm :: Order -> Html
renderForm order = formFor order [hsx|
    {(textField #customerId)}
    {submitButton}

|]