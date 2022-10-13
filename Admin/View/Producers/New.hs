module Admin.View.Producers.New where
import Admin.View.Prelude

data NewView = NewView { producer :: Producer }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        {renderForm producer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Producers" ProducersAction
                , breadcrumbText "New"
                ]

renderForm :: Producer -> Html
renderForm producer = formFor producer [hsx|
    {(textField #name) { required = True, autofocus = True }}
    {(textField #subject)}
    {(textareaField #description)}
    {submitButton}

|]
