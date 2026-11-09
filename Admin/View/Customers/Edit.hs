module Admin.View.Customers.Edit where
import qualified Data.Text as T

import Admin.View.Prelude

data EditView = EditView { customer :: Customer }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {renderOriginal customer}
        {renderForm customer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Customers" CustomersAction
                , breadcrumbLink [hsx|{fullName customer}|] (ShowCustomerAction customer.id)
                , breadcrumbText "Edit"
                , breadcrumbLink [hsx|<a href={DeleteCustomerAction customer.id} class="js-delete back-button">Delete</a>|] (DeleteCustomerAction customer.id)
                ]

-- | The name and address as the customer wrote them, before they were split
-- into their parts (migration 1794227624), to check the parts against. Goes
-- away with the old name and address columns.
renderOriginal :: Customer -> Html
renderOriginal customer
    | T.null name && T.null address = mempty
    | otherwise = [hsx|
        <div id="original-details" class="my-4 p-3 border rounded bg-gray-50 text-gray-700">
            <p class="font-medium">As the customer wrote it before the name and address were split</p>
            {when (not (T.null name)) nameRow}
            {when (not (T.null address)) addressRow}
        </div>
    |]
    where
        name = T.strip customer.name
        address = T.strip customer.address
        nameRow = [hsx|<p>Name: {name}</p>|]
        addressRow = [hsx|<p class="whitespace-pre-line">Address: {address}</p>|]

renderForm :: Customer -> Html
renderForm customer = formFor customer [hsx|
    {(textField #firstName) { required = True, autofocus = True }}
    {textField #lastName}
    {(textField #billingName) { fieldLabel = "Name on the invoice / Company name" }}
    {(textField #email) { required = True }}
    {(textField #phone) { required = True }}
    {textField #streetAddress}
    {textField #postalCode}
    {textField #city}
    {submitButton}

|]
