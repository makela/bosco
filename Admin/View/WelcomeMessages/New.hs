module Admin.View.WelcomeMessages.New where
import Admin.View.Prelude

data NewView = NewView { welcomeMessage :: WelcomeMessage }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        {renderForm welcomeMessage}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Welcome Messages" WelcomeMessagesAction
                , breadcrumbText "New"
                ]

renderForm :: WelcomeMessage -> Html
renderForm welcomeMessage = formFor welcomeMessage [hsx|
    {(textareaField #text)}
    {(checkboxField #isOrderingEnabled)}
    {submitButton}

|]
