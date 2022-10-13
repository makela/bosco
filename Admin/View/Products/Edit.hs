module Admin.View.Products.Edit where
import Admin.View.Prelude
import Admin.View.Products.New

data EditView = EditView
    { product :: Product
    , producers :: [Producer]
    }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {renderForm producers product}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Products" ProductsAction
                , breadcrumbLink [hsx|{product.name}|] (ShowProductAction product.id)
                , breadcrumbText "Edit"
                , breadcrumbLink [hsx|<a href={DeleteProductAction product.id} class="js-delete back-button">Delete</a>|] (DeleteProductAction product.id)
                ]
