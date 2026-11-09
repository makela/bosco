module Admin.View.Customers.Index where
import Admin.View.Prelude

data IndexView = IndexView { customers :: [Customer] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Email</th>
                        <th>Phone</th>
                    </tr>
                </thead>
                <tbody>{forEach customers renderCustomer}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText [hsx|<span>Customers</span>|]
                , breadcrumbLink "New" NewCustomerAction
                ]

renderCustomer :: Customer -> Html
renderCustomer customer = [hsx|
    <tr>
        <td><a href={ShowCustomerAction customer.id}>{fullName customer}</a></td>
        <td>{customer.email}</td>
        <td>{customer.phone}</td>
    </tr>
|]
