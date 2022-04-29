module Admin.View.WelcomeMessages.Edit where
import Admin.View.Prelude
import Admin.View.WelcomeMessages.New

data EditView = EditView { welcomeMessage :: WelcomeMessage }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        <h1>Edit WelcomeMessage</h1>
        {renderForm welcomeMessage}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "WelcomeMessages" WelcomeMessagesAction
                , breadcrumbText "Edit WelcomeMessage"
                ]
