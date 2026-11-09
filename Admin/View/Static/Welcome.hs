module Admin.View.Static.Welcome where
import Admin.View.Prelude

import Application.Demo (isDemoUser)
import Application.Permission (Permission (..), can, hasAnyRole)

data WelcomeView = WelcomeView { user :: !User }

instance View WelcomeView where
    html WelcomeView { .. } = [hsx|
        <a class="js-delete js-delete-no-confirm back-button float-right p-2" href={DeleteSessionAction}>Logout</a>
        {unless (isDemoUser user) changePassword}
        <ol class="my-4">
            {links}
        </ol>
|]
        where changePassword = [hsx|<a class="float-right p-2" href={NewPasswordAction}>Change password</a>|]
              links = [hsx|
                  {forEach (filter (\(permission, _, _) -> can user permission) menu) renderLink}
                  {noRole}
              |]
              -- Alphabetical, as the menu always was
              menu =
                  [ (ManageShop, "All ordered products", pathTo OrderedProductsAction)
                  , (ManageShop, "Customers", pathTo CustomersAction)
                  , (SeeEmailLists, "Emails for delivery info", pathTo EmailsForDeliveryInfoAction)
                  , (SeeEmailLists, "Emails for news letter", pathTo EmailsForNewsLetterAction)
                  , (SeeOrders, "Orders", pathTo OrdersAction)
                  , (ManageShop, "Payment Instructions", pathTo PaymentInstructionsAction)
                  , (ManageShop, "Producers", pathTo ProducersAction)
                  , (ManageShop, "Products", pathTo ProductsAction)
                  , (ManageShop, "Welcome Messages", pathTo WelcomeMessagesAction)
                  ] :: [(Permission, Text, Text)]
              renderLink (_, label, url) = [hsx|<li><a href={url}>{label}</a></li>|]
              noRole = unless (hasAnyRole user) [hsx|<li>Your login has no role yet: ask an admin for one.</li>|]
