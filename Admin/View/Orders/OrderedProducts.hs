module Admin.View.Orders.OrderedProducts where

import qualified Data.Map as Map

import Admin.View.Prelude

data OrderedProductsView = OrderedProductsView
    { producers             :: [Producer]
    , orderedProductsByYear :: Map.Map Integer [Include "productId" OrderedProduct]
    , years                 :: [Integer]
    }

instance View OrderedProductsView where
    html OrderedProductsView { .. } = [hsx|
        {breadcrumb}
        <table class="whitespace-nowrap">
        <thead>
            <tr>
                <th></th>
                {forEach years renderYearHeading}
            </tr>
        </thead>
        <tbody>
            {forEach producers (renderProducer years orderedProductsByYear)}
        </tbody>
        </table>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText "All ordered products"
                ]

renderYearHeading :: Integer -> Html
renderYearHeading year = [hsx|<th>{year}</th>|]

renderProducer :: [Integer] -> Map.Map Integer [Include "productId" OrderedProduct] -> Producer -> Html
renderProducer years orderedProductsByYear producer =
    let products = concat (Map.elems orderedProductsByYear)
            |> filter (\x -> x.productId.producerId == producer.id)
            |> Map.fromList . map (\x -> (x.productId.id, x))
            |> Map.elems
            |> sortOn (toLower . (.productId.name))
    in if null products then pure () else [hsx|
        <tr><th colspan={length years + 1}>{producer.name}</th></tr>
        {forEach products (renderOrderedProduct years orderedProductsByYear)}
    |]

renderOrderedProduct :: [Integer] -> Map.Map Integer [Include "productId" OrderedProduct] -> Include "productId" OrderedProduct -> Html
renderOrderedProduct years orderedProductsByYear orderedProduct = [hsx|
    <tr>
        <td>{orderedProduct.productId.name} ({orderedProduct.productId.package})</td>
        {forEach years (renderYearCount orderedProductsByYear orderedProduct.productId.id)}
    </tr>
|]

renderYearCount :: Map.Map Integer [Include "productId" OrderedProduct] -> Id' "products" -> Integer -> Html
renderYearCount orderedProductsByYear productId year =
    let quantity = Map.findWithDefault [] year orderedProductsByYear
            |> filter (\x -> x.productId.id == productId)
            |> map (.quantity)
            |> sum
    in [hsx|<td>{quantity}</td>|]
