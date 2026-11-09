-- | What each kind of admin user may do. A user has one or more roles
-- (is_admin, is_deliverer, is_promoter) and may do whatever any of them
-- allows; an admin may do everything. Controllers, menus and buttons ask
-- 'can', never the roles themselves, so a new role is a change here only.
module Application.Permission
    ( Permission (..)
    , can
    , hasAnyRole
    ) where

import IHP.Prelude
import Generated.Types

data Permission
    = SeeOrders
      -- ^ The order list and full order pages, with addresses and phones
    | CreateOrders
      -- ^ An order taken on the customer's behalf, from the admin
    | MarkDelivered
    | ManageOrders
      -- ^ Mark invoiced or paid, cancel, email the invoice again
    | SeeEmailLists
    | EditShopTexts
      -- ^ Product names, descriptions and packages, producers' subjects and
      -- descriptions: what a translator needs, not prices or the catalog
    | ManageShop
      -- ^ Products, producers, customers, the shop's texts and payment
      -- instructions, the ordered products summary
    deriving (Eq, Show, Enum, Bounded)

can :: User -> Permission -> Bool
can user permission =
    user.isAdmin
    || (user.isDeliverer && permission `elem` deliverer)
    || (user.isPromoter && permission `elem` promoter)
  where
    deliverer = [SeeOrders, CreateOrders, MarkDelivered]
    promoter = [SeeOrders, SeeEmailLists, EditShopTexts]

-- | A user without any role can log in but do nothing
hasAnyRole :: User -> Bool
hasAnyRole user = user.isAdmin || user.isDeliverer || user.isPromoter
