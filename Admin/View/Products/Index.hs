module Admin.View.Products.Index where
import Admin.View.Prelude
import Web.View.Orders.New (formatMoney)

data IndexView = IndexView
    { products :: [Include "producerId" Product] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table whitespace-nowrap">
                <thead>
                    <tr>
                        <th>Producer</th>
                        <th>Name</th>
                        <th>Package</th>
                        <th>Price</th>
                    </tr>
                </thead>
                <tbody>{forEach products renderProduct}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText "Products"
                , breadcrumbLink "New" NewProductAction
                ]

renderProduct :: Include "producerId" Product -> Html
renderProduct product = [hsx|
    <tr>
        <td>{product.producerId.name}</td>
        <td><a href={ShowProductAction product.id}>{product.name}</a></td>
        <td>{product.package}</td>
        <td>{formatMoney product.price}</td>
    </tr>
|]
