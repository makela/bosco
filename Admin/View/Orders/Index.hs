module Admin.View.Orders.Index where
import Admin.View.Prelude

data IndexView = IndexView { orders :: [Order] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Order</th>
                        <th></th>
                        <th></th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach orders renderOrder}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Orders" OrdersAction
                ]

renderOrder :: Order -> Html
renderOrder order = [hsx|
    <tr>
        <td>{order}</td>
        <td><a href={ShowOrderAction order.id}>Show</a></td>
    </tr>
|]
