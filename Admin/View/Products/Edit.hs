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
        <h1>Edit Product</h1>
        {renderForm producers product}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Products" ProductsAction
                , breadcrumbText "Edit Product"
                ]
