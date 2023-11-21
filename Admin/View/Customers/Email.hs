module Admin.View.Customers.Email where
import Admin.View.Prelude

import Admin.View.Orders.Index (renderYearSelect)

data EmailView = EmailView { emails :: [Text] }

instance View EmailView where
    html EmailView { .. } = [hsx|
        {intercalate ", " emails}
    |]

data YearlyEmailView = YearlyEmailView
    { emails :: [Text]
    , year   :: Integer
    , years  :: [Integer]
    }

instance View YearlyEmailView where
    html YearlyEmailView { .. } = [hsx|
        <form method="GET" action={EmailsForDeliveryInfoAction}>
            {renderYearSelect years year}
        </form>
        {intercalate ", " emails}
    |]
