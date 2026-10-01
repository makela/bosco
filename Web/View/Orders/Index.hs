module Web.View.Orders.Index where
import Web.View.Prelude

import qualified Text.MMark as MMark

import Application.Localization

data IndexView = IndexView
    { message :: Maybe WelcomeMessage
    , year    :: Text
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <p>{renderMarkdown $ maybe "" (.text) message}</p>
        {orderButton}
        <a href={NewEmailAction} data-turbolinks="false">{l10nText LSubscribe}</a>
    |]
        where
            orderButton = if maybe False (.isOrderingEnabled) message
                          then [hsx|<a href={NewOrderAction} class="btn" data-turbolinks="false">{l10nText LFillOrder}</a>|]
                          else [hsx||]

renderMarkdown text = case text |> MMark.parse "" of
    Left error     -> "Markdown error"
    Right markdown -> MMark.render markdown |> tshow |> preEscapedToHtml
