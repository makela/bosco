module Web.View.Orders.New where
import Numeric
import Web.View.Prelude

import qualified Data.Map as Map
import qualified Data.Text as T

import Application.Localization
import Web.View.Orders.Index (renderMarkdown)

type Orders = Map (Id Product) Int

type ProductsByProducers = Map (Id Producer) [Product]

data NewView = NewView
    { customer            :: Customer
    , orders              :: Orders
    , producers           :: [Producer]
    , productsByProducers :: ProductsByProducers
    , actionUrl           :: Text
    }

instance View NewView where
    html NewView { .. } = [hsx|
        <h1>{l10nText LOrderForm}</h1>
        <form method="POST" action={actionUrl}>
            <div class="flex flex-wrap">
                {forEach producers (renderProducer orders productsByProducers)}
            </div>
            {renderCustomerForm customer}
            <input type="submit" value={l10nText LSubmit} />
        </form>
    |]

renderCustomerForm :: Customer -> Html
renderCustomerForm customer = [hsx|
    <div class="flex flex-col my-6 space-y-2" id="form-group-customer_name">
        <label class="font-medium text-gray-700 " for="customer_name">{l10nText LName}</label>
        <input type="text" name="name" placeholder="" id="customer_name" required="required" value={customer.name}
               class={classes ["form-control", ("is-invalid", isInvalidName)]}>
        {nameFeedback}
    </div>
    <div class="flex flex-col my-6 space-y-2" id="form-group-customer_email">
        <label class="font-medium text-gray-700 " for="customer_email">{l10nText LEmail}</label>
        <input type="text" name="email" placeholder="" id="customer_email" required="required" value={customer.email}
               class={classes ["form-control", ("is-invalid", isInvalidEmail)]}>
        {emailFeedback}
    </div>
    <div class="flex flex-col my-6 space-y-2" id="form-group-customer_phone">
        <label class="font-medium text-gray-700 " for="customer_phone">{l10nText LPhone}</label>
        <input type="text" name="phone" placeholder="" id="customer_phone" required="required" value={customer.phone}
               class={classes ["form-control", ("is-invalid", isInvalidPhone)]}>
        {phoneFeedback}
    </div>
    <div class="flex flex-col my-6 space-y-2" id="form-group-customer_address">
        <label class="font-medium text-gray-700 " for="customer_address">{l10nText LAddress}</label>
        <input type="text" name="address" placeholder="" id="customer_address" required="required" value={customer.address}
               class={classes ["form-control", ("is-invalid", isInvalidAddress)]}>
        {addressFeedback}
    </div>
|]
    where
        isInvalidName = isJust (getValidationFailure #name customer)
        isInvalidEmail = isJust (getValidationFailure #email customer)
        isInvalidPhone = isJust (getValidationFailure #phone customer)
        isInvalidAddress = isJust (getValidationFailure #address customer)
        nameFeedback = case getValidationFailure #name customer of
            Just result -> [hsx|<div class="invalid-feedback">{result}</div>|]
            Nothing     -> mempty
        emailFeedback = case getValidationFailure #email customer of
            Just result -> [hsx|<div class="invalid-feedback">{result}</div>|]
            Nothing     -> mempty
        phoneFeedback = case getValidationFailure #phone customer of
            Just result -> [hsx|<div class="invalid-feedback">{result}</div>|]
            Nothing     -> mempty
        addressFeedback = case getValidationFailure #address customer of
            Just result -> [hsx|<div class="invalid-feedback">{result}</div>|]
            Nothing     -> mempty

renderProducer :: Orders -> ProductsByProducers -> Producer -> Html
renderProducer orders productsByProducer producer = [hsx|
    <fieldset>
        <h2>{producer.name}</h2>
        <p>{renderMarkdown producer.description}</p>
        <table class="whitespace-nowrap">
        <tbody>
        {forEach products (renderProduct orders)}
        </tbody>
        </table>
    </fieldset>
|]
    where products = fromMaybe [] $ Map.lookup producer.id productsByProducer

renderProduct :: Orders -> Product -> Html
renderProduct orders product = [hsx|
    <tr>
        <td>{product.name}</td>
        <td>{product.package}</td>
        <td>{price}</td>
        <td class="last"><input type="number" min="0" name={show product.id} value={count}> <span>kpl</span></td>
    </tr>
|]
    where
        price = formatMoney product.price
        count = maybe "" show $ Map.lookup product.id orders

formatMoney :: (Integral a, Num a) => a -> Text
formatMoney amount =
    fromIntegral amount
        |> (/100)
        |> \x -> showFFloat (Just 2) x " €"
        |> T.pack
        |> T.replace "." ","
        |> T.replace ",00" ""
