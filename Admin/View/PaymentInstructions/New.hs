module Admin.View.PaymentInstructions.New where
import Admin.View.Prelude

data NewView = NewView { paymentInstruction :: PaymentInstruction }

instance View NewView where
    html NewView { .. } = [hsx|
        {breadcrumb}
        {renderForm paymentInstruction}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Payment Instructions" PaymentInstructionsAction
                , breadcrumbText "New"
                ]

renderForm :: PaymentInstruction -> Html
renderForm paymentInstruction = formFor paymentInstruction [hsx|
    {(textareaField #text)}
    {submitButton}

|]
