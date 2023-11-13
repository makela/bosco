module Admin.View.Orders.Index where
import Admin.View.Prelude
import Data.Time.Format (formatTime)
import IHP.Controller.Param

data OrderBy = OrderByName | OrderByOrderedAt deriving Eq

instance ParamReader OrderBy where
    readParameter "ordered at" = Right OrderByOrderedAt
    readParameter _            = Right OrderByName

data OrderDir = OrderByAsc | OrderByDesc deriving Eq

instance ParamReader OrderDir where
    readParameter "descending" = Right OrderByDesc
    readParameter _            = Right OrderByAsc

data IndexView = IndexView
    { orders           :: [Include "customerId" Order]
    , q                :: Text
    , ordering         :: OrderBy
    , orderDir         :: OrderDir
    , excludePaid      :: Bool
    , excludeDelivered :: Bool
    , year             :: Integer
    , years            :: [Integer]
    }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <form method="GET" action={OrdersAction}>
            {renderYearSelect years year}
            {renderOrderBy ordering}
            {renderOrderDir orderDir}
            <br />
            <label>
                <input type="checkbox" name="excludePaid" checked={excludePaid} onchange="this.form.submit()"/>
                Exclude paid orders
            </label>
            <br />
            <label>
                <input type="checkbox" name="excludeDelivered" checked={excludeDelivered} onchange="this.form.submit()"/>
                Exclude delivered orders
            </label>
            <input type="search" placeholder="Search" name="q" value={q} />
        </form>
        <p>{n} orders</p>
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
                                <th>Paid At</th>
                                <th>Delivered At</th>
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
        <td>{fmap formatUTCTime order.paidAt}</td>
        <td>{fmap formatUTCTime order.deliveredAt}</td>
    </tr>
|]

renderYearSelect :: [Integer] -> Integer -> Html
renderYearSelect years year = [hsx|
    <label>
        Year
        <select name="year" onchange="this.form.submit()">
            {forEach years (renderYearOption year)}
        </select>
    </label>
|]

renderYearOption :: Integer -> Integer -> Html
renderYearOption selected year = [hsx|
    <option selected={year == selected}>{year}</option>
|]

renderOrderBy :: OrderBy -> Html
renderOrderBy ordering = [hsx|
    <label>
        Sort by
        <select name="ordering" onchange="this.form.submit()">
            <option selected={ordering == OrderByName}>customer</option>
            <option selected={ordering == OrderByOrderedAt}>ordered at</option>
        </select>
    </label>
|]

renderOrderDir :: OrderDir -> Html
renderOrderDir dir = [hsx|
    <label>
        Sort direction
        <select name="orderDir" onchange="this.form.submit()">
            <option selected={dir == OrderByAsc}>ascending</option>
            <option selected={dir == OrderByDesc}>descending</option>
        </select>
    </label>
|]

formatUTCTime :: UTCTime -> String
formatUTCTime = formatTime defaultTimeLocale "%Y-%m-%d %H:%M UTC"
