module Admin.View.Products.Index where
import Admin.View.CheckMark (isEnabled)
import Admin.View.Prelude
import Web.View.Orders.New (formatMoney)

data IndexView = IndexView
    { products :: [Include "producerId" Product]
    , canManageShop :: Bool
    }

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
                        <th>Enabled</th>
                    </tr>
                </thead>
                <tbody>{forEach products renderProduct}</tbody>
            </table>
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                ([ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText [hsx|<span>Products</span>|]
                ] <> [breadcrumbLink "New" NewProductAction | canManageShop])

renderProduct :: Include "producerId" Product -> Html
renderProduct product = [hsx|
    <tr>
        <td>{product.producerId.name}</td>
        <td><a href={ShowProductAction product.id}>{product.name}</a></td>
        <td>{product.package}</td>
        <td>{formatMoney product.price}</td>
        <td>{isEnabled product.enabled}</td>
    </tr>
|]
