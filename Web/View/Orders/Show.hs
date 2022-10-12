module Web.View.Orders.Show where
import Web.View.Prelude

import Web.View.Orders.New (formatMoney)

data ShowView = ShowView
    { orderId :: Id Order
    , customer :: Customer
    , orderedProducts :: [Include "productId" OrderedProduct]
    , totalSum :: Int
    }

instance View ShowView where
    html ShowView { .. } = [hsx|
        <h1>Lasku</h1>
        <a href="#" onclick="window.print(); return false" class="float-right">Tulosta</a>
        {renderCustomer customer}
        <table>
        <tbody>
            {forEach orderedProducts renderOrderedProduct}
            <tr class="font-bold">
                <td>Yhteensä</td>
                <td></td>
                <td>{formatMoney totalSum}</td>
            </tr>
        </tbody>
        </table>
        <p>TODO Maksuohjeet</p>
        <p>
            Mikäli huomasit tilauksessa virheen, voit vielä
            <a href={cancelAction} class="back-button">perua</a>
            sen.
        </p>
    |]
        where cancelAction = pathTo CancelOrderAction { orderId }

renderCustomer :: Customer -> Html
renderCustomer customer = [hsx|
    <p>
          {customer.name}
          <br/>
          {customer.email}
          <br/>
          {customer.phone}
          <br/>
          {customer.address}
    </p>
|]

renderOrderedProduct :: Include "productId" OrderedProduct -> Html
renderOrderedProduct orderedProduct = [hsx|
    <tr>
        <td>{orderedProduct.productId.name} ({orderedProduct.productId.package})</td>
        <td>{orderedProduct.quantity} * {formatMoney orderedProduct.productId.price}</td>
        <td>= {formatMoney (orderedProduct.productId.price * orderedProduct.quantity)}</td>
    </tr>
|]
