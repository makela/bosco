module Admin.View.Products.Edit where
import Admin.View.Prelude
import Admin.View.Products.New
import Web.View.Orders.New (formatMoney)

data EditView = EditView
    { product :: Product
    , producers :: [Producer]
    , canManageShop :: Bool
      -- ^ Otherwise only the texts can be edited
    }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {if canManageShop then renderForm producers product else renderTextForm producers product}
    |]
        where
            breadcrumb = renderBreadcrumb
                ([ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Products" ProductsAction
                , breadcrumbLink [hsx|{product.name}|] (ShowProductAction product.id)
                , breadcrumbText "Edit"
                ] <> [breadcrumbLink [hsx|<a href={DeleteProductAction product.id} class="js-delete back-button">Delete</a>|] (DeleteProductAction product.id) | canManageShop])

-- | The texts a promoter may change, the rest only shown
renderTextForm :: [Producer] -> Product -> Html
renderTextForm producers product = formFor product [hsx|
    <p>Producer: {producerName}</p>
    <p>Price: {formatMoney product.price}</p>
    <p>{shown}</p>
    {(textField #name) { required = True, autofocus = True }}
    {(textareaField #description)}
    {(textField #package) { required = True }}
    {submitButton}
|]
    where
        producerName = maybe "" (.name) (find (\p -> p.id == product.producerId) producers)
        shown = if product.enabled then "Shown on the order form" else "Not shown on the order form" :: Text
