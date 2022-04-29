module Admin.View.Static.Welcome where
import Admin.View.Prelude

data WelcomeView = WelcomeView

instance View WelcomeView where
    html WelcomeView = [hsx|
        <ul class="my-4">
            <li><a href={CustomersAction}>Customers</a></li>
            <li><a href={ProducersAction}>Producers</a></li>
            <li><a href={ProductsAction}>Products</a></li>
            <li><a href={WelcomeMessagesAction}>Welcome messages</a></li>
        </ul>
|]
