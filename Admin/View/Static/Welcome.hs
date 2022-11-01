module Admin.View.Static.Welcome where
import Admin.View.Prelude

data WelcomeView = WelcomeView

instance View WelcomeView where
    html WelcomeView = [hsx|
        <a class="js-delete js-delete-no-confirm back-button float-right p-2" href={DeleteSessionAction}>Logout</a>
        <ol class="my-4">
            <li><a href={OrderedProductsAction}>All ordered products</a></li>
            <li><a href={CustomersAction}>Customers</a></li>
            <li><a href={EmailsForDeliveryInfoAction}>Emails for delivery info</a></li>
            <li><a href={EmailsForNewsLetterAction}>Emails for news letter</a></li>
            <li><a href={OrdersAction}>Orders</a></li>
            <li><a href={PaymentInstructionsAction}>Payment Instructions</a></li>
            <li><a href={ProducersAction}>Producers</a></li>
            <li><a href={ProductsAction}>Products</a></li>
            <li><a href={WelcomeMessagesAction}>Welcome Messages</a></li>
        </ol>
|]
