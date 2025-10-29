module Web.View.Orders.Index where
import Web.View.Prelude

import qualified Text.MMark as MMark

data IndexView = IndexView
    { message :: Maybe WelcomeMessage
    , year    :: Text
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <p>{renderMarkdown $ maybe "" (.text) message}</p>
        {orderButton}
        <a href={NewEmailAction} data-turbolinks="false">Tilaa uutiskirje</a>
    |]
        where
            orderButton = if maybe False (.isOrderingEnabled) message
                          then [hsx|<a href={NewOrderAction} class="btn" data-turbolinks="false">Täytä tilaus</a>|]
                          else [hsx||]

renderMarkdown text = case text |> MMark.parse "" of
    Left error     -> "Jokin meni pieleen"
    Right markdown -> MMark.render markdown |> tshow |> preEscapedToHtml
