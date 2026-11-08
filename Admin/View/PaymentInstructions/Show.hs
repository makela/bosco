module Admin.View.PaymentInstructions.Show where
import Admin.View.Prelude
import Web.View.Orders.Index (renderMarkdown)

data ShowView = ShowView { paymentInstruction :: PaymentInstruction }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        {renderMarkdown paymentInstruction.text}

    |]
        where
            -- A demo's payment details are fixed, see Application.Demo
            breadcrumb = renderBreadcrumb $
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Payment Instructions" PaymentInstructionsAction
                , breadcrumbText (timeAgo paymentInstruction.publishedAt)
                ]
                <> [breadcrumbLink "Edit" (EditPaymentInstructionAction paymentInstruction.id) | not isDemo]
