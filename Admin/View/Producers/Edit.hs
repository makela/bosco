module Admin.View.Producers.Edit where
import Admin.View.Prelude
import Admin.View.Producers.New

data EditView = EditView
    { producer :: Producer
    , canManageShop :: Bool
      -- ^ Otherwise only the texts can be edited
    }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {if canManageShop then renderForm producer else renderTextForm producer}
    |]
        where
            breadcrumb = renderBreadcrumb
                ([ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Producers" ProducersAction
                , breadcrumbLink [hsx|{producer.name}|] (ShowProducerAction producer.id)
                , breadcrumbText "Edit"
                ] <> [breadcrumbLink [hsx|<a href={DeleteProducerAction producer.id} class="js-delete back-button">Delete</a>|] (DeleteProducerAction producer.id) | canManageShop])

-- | The texts a promoter may change, the rest only shown
renderTextForm :: Producer -> Html
renderTextForm producer = formFor producer [hsx|
    <p>Name: {producer.name}</p>
    <p>{shown}</p>
    {(textField #subject) { autofocus = True }}
    {(textareaField #description)}
    {submitButton}
|]
    where
        shown = if producer.enabled then "Shown on the order form" else "Not shown on the order form" :: Text
