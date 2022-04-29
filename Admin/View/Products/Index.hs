module Admin.View.Products.Index where
import Admin.View.Prelude

data IndexView = IndexView
    { products :: [Include "producerId" Product] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <a href={pathTo NewProductAction}>+ New</a>
        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Producer</th>
                        <th>Name</th>
                        <th>Package</th>
                        <th>Price</th>
                        <th></th>
                        <th></th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach products renderProduct}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Products" ProductsAction
                ]

renderProduct :: Include "producerId" Product -> Html
renderProduct product = [hsx|
    <tr>
        <td>{get #producerId product |> get #name}</td>
        <td>{get #name product}</td>
        <td>{get #package product}</td>
        <td>{get #price product}</td>
        <td><a href={ShowProductAction (get #id product)}>Show</a></td>
        <td><a href={EditProductAction (get #id product)} class="text-muted">Edit</a></td>
        <td><a href={DeleteProductAction (get #id product)} class="js-delete text-muted">Delete</a></td>
    </tr>
|]
