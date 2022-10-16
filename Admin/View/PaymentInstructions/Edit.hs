module Admin.View.PaymentInstructions.Edit where
import Admin.View.Prelude
import Admin.View.PaymentInstructions.New

data EditView = EditView { paymentInstruction :: PaymentInstruction }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {renderForm paymentInstruction}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Payment Instructions" PaymentInstructionsAction
                , breadcrumbLink (timeAgo paymentInstruction.publishedAt) (ShowPaymentInstructionAction paymentInstruction.id)
                , breadcrumbText "Edit"
                , breadcrumbLink [hsx|<a href={DeletePaymentInstructionAction paymentInstruction.id} class="js-delete back-button">Delete</a>|] (DeletePaymentInstructionAction paymentInstruction.id)
                ]
