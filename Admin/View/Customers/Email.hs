module Admin.View.Customers.Email where
import Admin.View.Prelude

data EmailView = EmailView { emails :: [Text] }

instance View EmailView where
    html EmailView { .. } = [hsx|
        {intercalate ", " emails}
    |]
