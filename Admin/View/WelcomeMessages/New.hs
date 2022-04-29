module Admin.View.WelcomeMessages.New where
import Admin.View.Prelude

data NewView = NewView { welcomeMessage :: WelcomeMessage }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        <h1>New WelcomeMessage</h1>
        {renderForm welcomeMessage}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "WelcomeMessages" WelcomeMessagesAction
                , breadcrumbText "New WelcomeMessage"
                ]

renderForm :: WelcomeMessage -> Html
renderForm welcomeMessage = formFor welcomeMessage [hsx|
    {(textareaField #text)}
    {(textField #picture)}
    {submitButton}

|]
