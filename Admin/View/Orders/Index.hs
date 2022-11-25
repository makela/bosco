module Admin.View.Orders.Index where
import Admin.View.Prelude
import Data.Time.Format (formatTime)

data IndexView = IndexView
    { orders :: [Include "customerId" Order]
    , q :: Text
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <form method="GET" action={OrdersAction}>
            <input type="search" placeholder="Search" name="q" value={q} />
            <p>{n} orders</p>
        </form>
        {tableOrNot}
    |]
        where
            n = length orders
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText "Orders"
                ]
            tableOrNot = if n == 0 then pure () else [hsx|
                <div class="table-responsive">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>Ordered At</th>
                                <th>Customer</th>
                            </tr>
                        </thead>
                        <tbody>{forEach orders renderOrder}</tbody>
                    </table>
                </div>
            |]

renderOrder :: Include "customerId" Order -> Html
renderOrder order = [hsx|
    <tr>
        <td><a href={ShowOrderAction order.id}>{formatUTCTime order.orderedAt}</a></td>
        <td>{order.customerId.name}</td>
    </tr>
|]

formatUTCTime :: UTCTime -> String
formatUTCTime = formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"
