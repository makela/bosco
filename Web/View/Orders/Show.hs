module Web.View.Orders.Show where
import Web.View.Orders.Index (renderMarkdown)
import Web.View.Orders.New (formatMoney)
import Web.View.Prelude

import qualified Data.Map as Map

import Application.Localization

type OrderedProductsByProducer = Map (Id' "producers") [OrderedProduct' (Id' "orders") Product]

data ShowView = ShowView
    { order                     :: Include "customerId" Order
    , producers                 :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , totalSum                  :: Int
    , paymentInstruction        :: Maybe PaymentInstruction
    }

instance View ShowView where
    html ShowView { .. } = [hsx|
        <h1>{l10nText LInvoice}</h1>
        {renderCustomer order.customerId}
        <table class="whitespace-nowrap">
        <tbody>
            {forEach producers (renderProducer orderedProductsByProducer)}
            {renderTotalSum totalSum}
        </tbody>
        </table>
        {renderPaymentInstruction order paymentInstruction}
        <p>{l10nText LPaymentSentToEmail}</p>
    |]

renderPaymentInstruction :: Include "customerId" Order -> Maybe PaymentInstruction -> Html
renderPaymentInstruction order paymentInstruction = case (order.paidAt, order.cancelledAt) of
    (Nothing, Nothing) -> [hsx|
            <h2>{l10nText LPaymentInstructions}</h2>
            {instructions}
        |]
    (_, Just _) -> [hsx|<p class="font-bold">Lasku on mitätöity.</p>|]
    (Just _, _) -> [hsx|<p class="font-bold">Lasku on maksettu.</p>|]

    where instructions = fmap (\x -> renderMarkdown x.text) paymentInstruction

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
        <td class="normal">{orderedProduct.productId.name} ({orderedProduct.productId.package})</td>
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
        <td>{l10nText LTotal}</td>
        <td></td>
        <td></td>
        <td></td>
        <td></td>
        <td class="last">{formatMoney totalSum}</td>
    </tr>
|]
