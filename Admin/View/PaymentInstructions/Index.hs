module Admin.View.PaymentInstructions.Index where
import Admin.View.Prelude

data IndexView = IndexView { paymentInstructions :: [PaymentInstruction] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Published</th>
                    </tr>
                </thead>
                <tbody>{forEach paymentInstructions renderPaymentInstruction}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            -- A demo's payment details are fixed, see Application.Demo
            breadcrumb = renderBreadcrumb $
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText [hsx|<span>Payment Instructions</span>|]
                ]
                <> [breadcrumbLink "New" NewPaymentInstructionAction | not isDemo]

renderPaymentInstruction :: PaymentInstruction -> Html
renderPaymentInstruction paymentInstruction = [hsx|
    <tr>
        <td><a href={ShowPaymentInstructionAction paymentInstruction.id}>{timeAgo paymentInstruction.publishedAt}</a></td>
    </tr>
|]
