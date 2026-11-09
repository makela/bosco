module Web.View.Orders.New where
import Numeric
import GHC.Records (HasField (getField))
import GHC.TypeLits (KnownSymbol)
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
    , unavailable         :: [Product]
      -- ^ Ordered products that can no longer be ordered
    , noProductsSelected  :: Bool
    }

instance View NewView where
    html NewView { .. } = [hsx|
        <h1>{l10nText LOrderForm}</h1>
        <form method="POST" action={actionUrl}>
            {renderUnavailable unavailable}
            {when noProductsSelected renderNoProductsSelected}
            <div class="flex flex-wrap">
                {forEach producers (renderProducer orders productsByProducers)}
            </div>
            {renderCustomerForm customer}
            <input type="submit" value={l10nText LSubmit} />
        </form>
    |]

renderUnavailable :: [Product] -> Html
renderUnavailable [] = mempty
renderUnavailable products = [hsx|
    <div class="unavailable-notice" role="alert">
        <p>{l10nText LNoLongerAvailable}</p>
        <ul>{forEach products renderName}</ul>
        <p>{l10nText LCheckOrderAndResubmit}</p>
    </div>
|]
    where renderName product = [hsx|<li>{product.name} ({product.package})</li>|]

renderNoProductsSelected :: Html
renderNoProductsSelected = [hsx|
    <div class="unavailable-notice" role="alert">
        <p>{l10nText LNoProductsSelected}</p>
    </div>
|]

renderCustomerForm :: Customer -> Html
renderCustomerForm customer = [hsx|
    {customerField customer #firstName "firstName" LFirstName "given-name"}
    {customerField customer #lastName "lastName" LLastName "family-name"}
    {customerField customer #billingName "billingName" LBillingName "organization"}
    {customerField customer #email "email" LEmail "email"}
    {customerField customer #phone "phone" LPhone "tel"}
    {customerField customer #streetAddress "streetAddress" LStreetAddress "street-address"}
    {customerField customer #postalCode "postalCode" LPostalCode "postal-code"}
    {customerField customer #city "city" LCity "address-level2"}
|]

-- | A text input of the customer form with its label and validation message.
-- Every field but the last name and the name for the invoice is required.
customerField :: forall name. (KnownSymbol name, HasField name Customer Text)
    => Customer -> Proxy name -> Text -> Localizable -> Text -> Html
customerField customer fieldProxy fieldName label autocomplete = [hsx|
    <div class="flex flex-col my-6 space-y-2" id={"form-group-customer_" <> fieldName}>
        <label class="font-medium text-gray-700 " for={inputId}>{l10nText label}</label>
        <input type="text" name={fieldName} placeholder="" id={inputId} required={fieldName `notElem` optionalFields}
               autocomplete={autocomplete} value={getField @name customer}
               class={classes ["form-control", ("is-invalid", isJust failure)]}>
        {feedback}
    </div>
|]
    where
        inputId = "customer_" <> fieldName
        optionalFields = ["lastName", "billingName"] :: [Text]
        failure = getValidationFailure fieldProxy customer
        feedback = case failure of
            Just result -> [hsx|<div class="invalid-feedback">{result}</div>|]
            Nothing     -> mempty

renderProducer :: Orders -> ProductsByProducers -> Producer -> Html
renderProducer orders productsByProducer producer = [hsx|
    <fieldset>
        <h2>{producer.name}</h2>
        <p>{renderMarkdown producer.description}</p>
        <div class="products">
            {forEach products (renderProduct orders)}
        </div>
    </fieldset>
|]
    where products = fromMaybe [] $ Map.lookup producer.id productsByProducer

-- | One product row. On phones: name and package/price on the left, the
-- quantity on the right. On wider screens the parts line up in columns.
-- See div.product in tailwind/app.css.
renderProduct :: Orders -> Product -> Html
renderProduct orders product = [hsx|
    <div class="product">
        <span class="product-name">{product.name}</span>
        <span class="product-details">
            <span class="product-package">{product.package}</span>
            <span class="product-price">{price}</span>
        </span>
        <span class="product-quantity">
            <input type="number" min="0" name={show product.id} value={count} aria-label={product.name <> ", " <> product.package}> {l10nText LPieces}
        </span>
        <span class="product-description">{product.description}</span>
    </div>
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
