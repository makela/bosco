module Web.Mail.Orders.Order where
import IHP.MailPrelude
import Application.Customer (addressLines, fullName, nameLines)
import Web.View.Orders.Index (renderMarkdown)
import Web.View.Orders.New (formatMoney)
import Web.View.Orders.Show (OrderedProductsByProducer)
import Web.View.Prelude

import Application.Localization
import Application.Settings (MailAddresses (..))
import IHP.ControllerSupport (getAppConfig)

import qualified Data.Map as Map

data OrderMail = OrderMail
    { order                     :: Include "customerId" Order
    , producers                 :: [Producer]
    , orderedProductsByProducer :: OrderedProductsByProducer
    , totalSum                  :: Int
    , paymentInstruction        :: Maybe PaymentInstruction
    }

instance BuildMail OrderMail where
    subject = l10nText LSiteTitle
    to OrderMail { .. } = Address { addressName = Just (fullName order.customerId), addressEmail = order.customerId.email }
    -- The instance's, MAIL_FROM and MAIL_REPLY_TO (Config.hs)
    from = (getAppConfig @MailAddresses).mailFrom
    replyTo _ = (getAppConfig @MailAddresses).mailReplyTo
    html OrderMail { .. } = [hsx|
        <h1>{l10nText LInvoice}</h1>
        <div>
          {forEach (nameLines order.customerId) renderLine}
          <p>{order.customerId.email}</p>
          <p>{order.customerId.phone}</p>
          {forEach (addressLines order.customerId) renderLine}
        </div>
        <table style="white-space: nowrap">
        <tbody>
            {forEach producers (renderProducer orderedProductsByProducer)}
            <tr style="font-weight: bold">
                <td>{l10nText LTotal}</td>
                <td></td>
                <td></td>
                <td></td>
                <td></td>
                <td style="text-align: right">{formatMoney totalSum}</td>
            </tr>
        </tbody>
        </table>
        <h2>{l10nText LPaymentInstructions}</h2>
        {instructions}
    |]
        where
            instructions = fmap (\x -> renderMarkdown x.text) paymentInstruction
            renderLine line = [hsx|<p>{line}</p>|]
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
                    <td>{formatMoney orderedProduct.unitPrice}</td>
                    <td>=</td>
                    <td style="text-align: right">{formatMoney (orderedProduct.unitPrice * orderedProduct.quantity)}</td>
                </tr>
            |]
