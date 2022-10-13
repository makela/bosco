module Web.View.Orders.Show where
import Web.View.Prelude

import qualified Data.Map as Map

import Web.View.Orders.New (formatMoney)

type OrderedProductsByProducer = Map (Id' "producers") [OrderedProduct' (Id' "orders") Product]

data ShowView = ShowView
    { order :: Include "customerId" Order
    , producers :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , totalSum :: Int
    }

instance View ShowView where
    html ShowView { .. } = [hsx|
        <h1>Lasku</h1>
        {cancelOption}
        {renderCustomer order.customerId}
        <table class="whitespace-nowrap">
        <tbody>
            {forEach producers (renderProducer orderedProductsByProducer)}
            {renderTotalSum totalSum}
        </tbody>
        </table>
        <h2>Maksuohjeet</h2>
        <p>REMOVED-ACCOUNT-HOLDER</p>
        <p>IBAN REMOVED-IBAN</p>
        <p>BIC REMOVED-BIC (last digit is a zero)</p>
        <p>via Vittorio Emanuele II 15/17 91011 Alcamo TP,  ITALIA</p>
        <p>
            Voit myös
            <a href="#" onclick="window.print(); return false">tulostaa</a>
            laskun maksaaksesi sen myöhemmin.
        </p>
    |]
        where
            cancelOption = case (order.paidAt, order.cancelledAt) of
                (Nothing, Nothing) -> [hsx|
                        <p>
                            Mikäli huomaat laskussa virheen, voit vielä
                            <a href={CancelOrderAction order.id} class="back-button">perua</a>
                            sen.
                        </p>
                    |]
                (_, Just _) -> [hsx|<p class="font-bold">Lasku on mitätöity.</p>|]
                (Just _, _) -> [hsx|<p class="font-bold">Lasku on maksettu.</p>|]

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

renderTotalSum :: Int -> Html
renderTotalSum totalSum = [hsx|
    <tr class="font-bold">
        <td>Yhteensä</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td class="last">{formatMoney totalSum}</td>
    </tr>
|]
