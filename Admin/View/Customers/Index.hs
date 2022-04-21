module Admin.View.Customers.Index where
import Admin.View.Prelude

data IndexView = IndexView { customers :: [Customer] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <h1>Index<a href={pathTo NewCustomerAction} class="btn btn-primary ml-4">+ New</a></h1>
        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Email</th>
                        <th>Phone</th>
                        <th></th>
                        <th></th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach customers renderCustomer}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Customers" CustomersAction
                ]

renderCustomer :: Customer -> Html
renderCustomer customer = [hsx|
    <tr>
        <td>{get #name customer}</td>
        <td>{get #email customer}</td>
        <td>{get #phone customer}</td>
        <td><a href={ShowCustomerAction (get #id customer)}>Show</a></td>
        <td><a href={EditCustomerAction (get #id customer)} class="text-muted">Edit</a></td>
        <td><a href={DeleteCustomerAction (get #id customer)} class="js-delete text-muted">Delete</a></td>
    </tr>
|]
