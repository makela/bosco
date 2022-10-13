module Admin.View.WelcomeMessages.Show where
import Admin.View.Prelude
import Web.View.Orders.Index (renderMarkdown)

data ShowView = ShowView { welcomeMessage :: WelcomeMessage }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        {renderMarkdown welcomeMessage.text}

    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Welcome Messages" WelcomeMessagesAction
                , breadcrumbText (timeAgo welcomeMessage.publishedAt)
                , breadcrumbLink "Edit" (EditWelcomeMessageAction welcomeMessage.id)
                ]
