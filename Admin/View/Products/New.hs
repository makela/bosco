module Admin.View.Products.New where
import Admin.View.Prelude

data NewView = NewView
    { product :: Product
    , producers :: [Producer]
    }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        <h1>New Product</h1>
        {renderForm producers product}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Products" ProductsAction
                , breadcrumbText "New Product"
                ]

instance CanSelect Producer where
    type SelectValue Producer = Id Producer
    selectValue = get #id
    selectLabel = get #name

renderForm :: [Producer] -> Product -> Html
renderForm producers product = formFor product [hsx|
    {(selectField #producerId producers) { required = True, autofocus = True }}
    {(textField #name) { required = True }}
    {(textareaField #description)}
    {(textField #package) { required = True }}
    {(textField #price) { required = True, helpText = "In cents" }}
    {submitButton}

|]
