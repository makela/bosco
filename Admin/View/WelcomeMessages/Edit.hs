module Admin.View.WelcomeMessages.Edit where
import Admin.View.Prelude
import Admin.View.WelcomeMessages.New

data EditView = EditView { welcomeMessage :: WelcomeMessage }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {renderForm welcomeMessage}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Welcome Messages" WelcomeMessagesAction
                , breadcrumbLink (timeAgo welcomeMessage.publishedAt) (ShowWelcomeMessageAction welcomeMessage.id)
                , breadcrumbText "Edit"
                , breadcrumbLink [hsx|<a href={DeleteWelcomeMessageAction welcomeMessage.id} class="js-delete back-button">Delete</a>|] (DeleteWelcomeMessageAction welcomeMessage.id)
                ]
