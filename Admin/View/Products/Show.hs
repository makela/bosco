module Admin.View.Products.Show where
import Admin.View.Prelude
import Web.View.Orders.New (formatMoney)

data ShowView = ShowView { product :: Include "producerId" Product }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <p class="font-bold">{product.producerId.name}</p>
        <p>{product.description}</p>
        <p>{formatMoney product.price} / {product.package}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Products" ProductsAction
                , breadcrumbText [hsx|{product.name}|]
                , breadcrumbLink "Edit" (EditProductAction product.id)
                ]
