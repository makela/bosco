module Web.Mail.Orders.Order where
import IHP.MailPrelude
import Web.View.Orders.Index (renderMarkdown)
import Web.View.Orders.New (formatMoney)
import Web.View.Orders.Show (OrderedProductsByProducer)
import Web.View.Prelude

import qualified Data.Map as Map

data OrderMail = OrderMail
    { order                     :: Include "customerId" Order
    , producers                 :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , totalSum                  :: Int
    , paymentInstruction        :: Maybe PaymentInstruction
    }

instance BuildMail OrderMail where
    subject = "Bosco Falconeria Öljytilaus"
    to OrderMail { .. } = Address { addressName = Just order.customerId.name, addressEmail = order.customerId.email }
    from = "postmaster@boscofalconeria.it"
    replyTo OrderMail { .. } = Just Address { addressName = Just "Olive Oil Bosco Falconeria", addressEmail = "oliveoil@boscofalconeria.it" }
    html OrderMail { .. } = [hsx|
        <h1>Lasku</h1>
        <div>
          <p>{order.customerId.name}</p>
          <p>{order.customerId.email}</p>
          <p>{order.customerId.phone}</p>
          <p>{order.customerId.address}</p>
        </div>
        <table style="white-space: nowrap">
        <tbody>
            {forEach producers (renderProducer orderedProductsByProducer)}
            <tr style="font-weight: bold">
                <td>Yhteensä</td>
                <td></td>
                <td></td>
                <td></td>
                <td></td>
                <td style="text-align: right">{formatMoney totalSum}</td>
            </tr>
        </tbody>
        </table>
        <h2>Maksuohjeet</h2>
        {instructions}
    |]
        where
            instructions = fmap (\x -> renderMarkdown x.text) paymentInstruction
            renderProducer orderedProductsByProducer producer =
                case Map.lookup producer.id orderedProductsByProducer of
                    Nothing -> pure ()
                    Just orderedProducts -> [hsx|
                            <tr><td colspan="4" style="font-weight: bold">{producer.name}</td></tr>
                            {forEach orderedProducts renderOrderedProduct}
                        |]
            renderOrderedProduct orderedProduct = [hsx|
                <tr>
                    <td>{orderedProduct.productId.name} ({orderedProduct.productId.package})</td>
                    <td>{orderedProduct.quantity}</td>
                    <td>*</td>
                    <td>{formatMoney orderedProduct.productId.price}</td>
                    <td>=</td>
                    <td style="text-align: right">{formatMoney (orderedProduct.productId.price * orderedProduct.quantity)}</td>
                </tr>
            |]
