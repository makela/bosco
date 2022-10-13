module Web.View.Orders.Index where
import Web.View.Prelude

import qualified Text.MMark as MMark

data IndexView = IndexView
    { message :: Maybe WelcomeMessage
    , year :: Text
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <h1>Bosco Falconeria {year}</h1>
        <p>{renderMarkdown $ maybe "" (get #text) message}</p>
        <a href={NewOrderAction} class="btn">Täytä tilaus</a>
    |]

renderMarkdown text = case text |> MMark.parse "" of
    Left error -> "Jokin meni pieleen"
    Right markdown -> MMark.render markdown |> tshow |> preEscapedToHtml
