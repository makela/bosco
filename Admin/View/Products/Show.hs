module Admin.View.Products.Show where
import Admin.View.Prelude

data ShowView = ShowView { product :: Product }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <h1>Show Product</h1>
        <p>{product}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                            [ breadcrumbLink "Products" ProductsAction
                            , breadcrumbText "Show Product"
                            ]