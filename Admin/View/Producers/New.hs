module Admin.View.Producers.New where
import Admin.View.Prelude

data NewView = NewView { producer :: Producer }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        <h1>New Producer</h1>
        {renderForm producer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Producers" ProducersAction
                , breadcrumbText "New Producer"
                ]

renderForm :: Producer -> Html
renderForm producer = formFor producer [hsx|
    {(textField #name) { required = True, autofocus = True }}
    {(textField #subject) { required = True }}
    {(textareaField #description)}
    {submitButton}

|]
