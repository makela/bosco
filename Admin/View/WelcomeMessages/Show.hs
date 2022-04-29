module Admin.View.WelcomeMessages.Show where
import Admin.View.Prelude

data ShowView = ShowView { welcomeMessage :: WelcomeMessage }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <h1>Show WelcomeMessage</h1>
        <p>{welcomeMessage}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                            [ breadcrumbLink "WelcomeMessages" WelcomeMessagesAction
                            , breadcrumbText "Show WelcomeMessage"
                            ]