module Admin.View.Orders.Show where
import Admin.View.Prelude
import Web.View.Orders.New (formatMoney)

data ShowView = ShowView
    { order :: Include "customerId" Order
    , orderedProducts :: [Include "productId" OrderedProduct]
    , totalSum :: Int
    }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <h1>{order.customerId.name}</h1>
        <p>{order.customerId.email}</p>
        <p>{order.customerId.phone}</p>

        <table>
        <tbody>
            {forEach orderedProducts renderProduct}
            <tr class="font-bold">
                <td>Yhteensä</td>
                <td></td>
                <td>{formatMoney totalSum}</td>
            </tr>
        </tbody>
        </table>

        {renderActionButtons order}

    |]
        where
            breadcrumb = renderBreadcrumb
                            [ breadcrumbLink "Orders" OrdersAction
                            , breadcrumbText "Show Order"
                            ]

renderProduct :: Include "productId" OrderedProduct -> Html
renderProduct product = [hsx|
    <tr>
        <td>{product.productId.name}</td>
        <td>{product.quantity} * {formatMoney product.productId.price}</td>
        <td>= {formatMoney (product.quantity * product.productId.price)}</td>
    </tr>
|]

renderActionButtons :: Include "customerId" Order -> Html
renderActionButtons order =
    case (order.cancelledAt, order.paidAt) of
        (Nothing, Nothing) -> [hsx|
            <a href={CancelOrderAction order.id} class="back-button">Peruuta tilaus</a>
            <a href={MarkPaidOrderAction order.id} class="float-right">Merkitse maksetuksi</a>
        |]
        _ -> pure ()
