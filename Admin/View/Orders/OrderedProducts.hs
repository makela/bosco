module Admin.View.Orders.OrderedProducts where

import qualified Data.Map as Map

import Admin.View.Orders.Index (renderYearSelect)
import Admin.View.Prelude
import Web.View.Orders.Show (OrderedProductsByProducer)

data OrderedProductsView = OrderedProductsView
    { producers                 :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , year                      :: Integer
    , years                     :: [Integer]
    }

instance View OrderedProductsView where
    html OrderedProductsView { .. } = [hsx|
        {breadcrumb}
        <form method="GET" action={OrderedProductsAction}>
            {renderYearSelect years year}
        </form>
        <table class="whitespace-nowrap">
        <tbody>
            {forEach producers (renderProducer orderedProductsByProducer)}
        </tbody>
        </table>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText "All ordered products"
                ]

renderProducer :: OrderedProductsByProducer -> Producer -> Html
renderProducer orderedProductsByProducer producer =
    case Map.lookup producer.id orderedProductsByProducer of
        Nothing -> pure ()
        Just orderedProducts -> [hsx|
                <tr><td colspan="2" class="font-bold">{producer.name}</td></tr>
                {forEach orderedProducts renderOrderedProduct}
            |]

renderOrderedProduct :: Include "productId" OrderedProduct -> Html
renderOrderedProduct orderedProduct = [hsx|
    <tr>
        <td>{orderedProduct.productId.name} ({orderedProduct.productId.package})</td>
        <td>{orderedProduct.quantity}</td>
    </tr>
|]
