module Web.View.Orders.Show where
import Web.View.Prelude

import qualified Data.Map as Map

import Web.View.Orders.New (formatMoney)

type OrderedProductsByProducer = Map (Id' "producers") [OrderedProduct' (Id' "orders") Product]

data ShowView = ShowView
    { orderId :: Id Order
    , customer :: Customer
    , producers :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , totalSum :: Int
    }

instance View ShowView where
    html ShowView { .. } = [hsx|
        <h1>Lasku</h1>
        {renderCustomer customer}
        <table class="whitespace-nowrap">
        <tbody>
            {forEach producers (renderProducer orderedProductsByProducer)}
            <tr class="font-bold">
                <td>Yhteensä</td>
                <td></td>
                <td></td>
                <td></td>
                <td></td>
                <td class="last">{formatMoney totalSum}</td>
            </tr>
        </tbody>
        </table>
        <p>
            Mikäli huomasit tilauksessa virheen, voit vielä
            <a href={cancelAction} class="back-button">perua</a>
            sen.
        </p>
        <h2>Maksuohjeet</h2>
        <p>
            REMOVED-ACCOUNT-HOLDER
            <br/>
            IBAN REMOVED-IBAN
            <br/>
            BIC REMOVED-BIC      (last digit is a zero)
            <br/>
            via Vittorio Emanuele II 15/17 91011 Alcamo TP,  ITALIA
        </p>
        <p>
            Voit myös <a href="#" onclick="window.print(); return false">tulostaa</a> laskun maksaaksesi sen myöhemmin.
        </p>
    |]
        where cancelAction = pathTo CancelOrderAction { .. }

renderCustomer :: Customer -> Html
renderCustomer customer = [hsx|
    <div class="flex">
      <p>{customer.name}</p>
      <p>{customer.email}</p>
      <p>{customer.phone}</p>
      <p>{customer.address}</p>
    </div>
|]

renderProducer :: OrderedProductsByProducer -> Producer -> Html
renderProducer orderedProductsByProducer producer =
    case Map.lookup producer.id orderedProductsByProducer of
        Nothing -> pure ()
        Just orderedProducts -> [hsx|
                <tr><td colspan="4" class="font-bold">{producer.name}</td></tr>
                {forEach orderedProducts renderOrderedProduct}
            |]

renderOrderedProduct :: Include "productId" OrderedProduct -> Html
renderOrderedProduct orderedProduct = [hsx|
    <tr>
        <td>{orderedProduct.productId.name} ({orderedProduct.productId.package})</td>
        <td>{orderedProduct.quantity}</td>
        <td>*</td>
        <td>{formatMoney orderedProduct.productId.price}</td>
        <td>=</td>
        <td class="last">{formatMoney (orderedProduct.productId.price * orderedProduct.quantity)}</td>
    </tr>
|]
