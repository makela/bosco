module Admin.View.Orders.Index where

import qualified Data.Map as Map

import Admin.View.Prelude
import Data.Time.Format (formatTime)
import IHP.Controller.Param
import Web.View.Orders.New (formatMoney)

data OrderBy
    = OrderByName
    | OrderByOrderedAt
    | OrderByPrice
    deriving Eq

instance ParamReader OrderBy where
    readParameter "price"      = Right OrderByPrice
    readParameter "ordered at" = Right OrderByOrderedAt
    readParameter _            = Right OrderByName

data OrderDir = OrderByAsc | OrderByDesc deriving Eq

instance ParamReader OrderDir where
    readParameter "descending" = Right OrderByDesc
    readParameter _            = Right OrderByAsc

data IndexView = IndexView
    { orders           :: [Include "customerId" Order]
    , priceMap         :: Map (Id Order) Int
    , q                :: Text
    , ordering         :: OrderBy
    , orderDir         :: OrderDir
    , excludeInvoiced  :: Bool
    , excludePaid      :: Bool
    , excludeDelivered :: Bool
    , year             :: Integer
    , years            :: [Integer]
    , isAdmin          :: Bool
      -- ^ Only admins can mark orders paid
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
                <input type="checkbox" name="excludeInvoiced" checked={excludeInvoiced} onchange="this.form.submit()"/>
                Exclude invoiced orders
            </label>
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
                , breadcrumbLink "New" NewOrderAction
                ]
            tableOrNot = unless (n == 0) [hsx|
                <div class="table-responsive">
                    <table class="table">
                        <thead>
                            <tr>
                                <th>Ordered</th>
                                <th>Customer</th>
                                <th>Invoiced</th>
                                <th>Price</th>
                                <th>Paid</th>
                                <th>Delivered</th>
                            </tr>
                        </thead>
                        <tbody>{forEach orders (renderOrder isAdmin priceMap)}</tbody>
                    </table>
                </div>
            |]

renderOrder :: Bool -> Map (Id Order) Int -> Include "customerId" Order -> Html
renderOrder isAdmin priceMap order = [hsx|
    <tr>
        <td><a href={ShowOrderAction order.id}>{formatUTCTime order.orderedAt}</a></td>
        <td class="normal">{order.customerId.name}</td>
        <td>{fmap formatUTCTime order.invoicedAt}</td>
        <td>{fmap formatMoney $ Map.lookup order.id priceMap}</td>
        <td>{showOrMarkPaid isAdmin order}</td>
        <td>{fmap formatUTCTime order.deliveredAt}</td>
    </tr>
|]

showOrMarkPaid :: Bool -> Include "customerId" Order -> Html
showOrMarkPaid isAdmin order =
    case order.paidAt of
      Just paidAt -> [hsx|{formatUTCTime paidAt}|]
      Nothing | not isAdmin -> mempty
      Nothing     -> [hsx|
                    <form method="POST" action={UpdateMarkPaidOrderAction order.id}>
                        <input type="submit" class="btn-small" value="Mark as paid" />
                    </form>
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
            <option selected={ordering == OrderByPrice}>price</option>
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
