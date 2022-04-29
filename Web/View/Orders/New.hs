module Web.View.Orders.New where
import Web.View.Prelude

data NewView = NewView
    { order :: Order
    , products :: [Product]
    }

instance View NewView where
    html NewView { .. } = [hsx|
        <h1>Tilauslomake</h1>
        <form method="POST" action={CreateOrderAction}>
            <input type="submit" value="Tilaa" />
        </form>
    |]
