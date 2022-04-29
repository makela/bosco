module Web.View.Orders.Index where
import Web.View.Prelude

data IndexView = IndexView
    { message :: Maybe WelcomeMessage
    , year :: Text
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        <h1>Bosco Falconeria Tilauslomake {year}</h1>
				<p>{maybe "" (get #text) message}</p>
				<a href={pathTo NewOrderAction} class="btn btn-primary ml-4">Make an order</a>
    |]

renderOrder :: Order -> Html
renderOrder order = [hsx|
    <tr>
        <td>{order}</td>
        <td><a href={ShowOrderAction (get #id order)}>Show</a></td>
        <td><a href={EditOrderAction (get #id order)} class="text-muted">Edit</a></td>
        <td><a href={DeleteOrderAction (get #id order)} class="js-delete text-muted">Delete</a></td>
    </tr>
|]
