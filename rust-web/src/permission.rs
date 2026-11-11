//! What each kind of admin user may do, the IHP app's
//! `Application/Permission.hs`. A user has one or more roles and may do
//! whatever any of them allows; an admin may do everything. Pages ask
//! `can`, never the roles themselves.

use crate::db::Roles;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Permission {
    /// The order list and full order pages, with addresses and phones
    SeeOrders,
    /// An order taken on the customer's behalf, from the admin
    CreateOrders,
    MarkDelivered,
    /// Mark invoiced or paid, cancel, email the invoice again
    ManageOrders,
    SeeEmailLists,
    /// All ordered products: how much of each was ordered, per year
    SeeOrderedProducts,
    /// Product names, descriptions and packages, producers' subjects and
    /// descriptions: what a translator needs, not prices or the catalog
    EditShopTexts,
    /// Products, producers, customers, the shop's texts and payment
    /// instructions
    ManageShop,
}

use Permission::*;

const DELIVERER: &[Permission] = &[SeeOrders, CreateOrders, MarkDelivered];
const PROMOTER: &[Permission] = &[SeeOrders, SeeEmailLists, SeeOrderedProducts, EditShopTexts];

impl Roles {
    pub fn can(self, permission: Permission) -> bool {
        self.admin
            || (self.deliverer && DELIVERER.contains(&permission))
            || (self.promoter && PROMOTER.contains(&permission))
    }

    /// A user without any role can log in but do nothing
    pub fn any(self) -> bool {
        self.admin || self.deliverer || self.promoter
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL: [Permission; 8] = [
        SeeOrders,
        CreateOrders,
        MarkDelivered,
        ManageOrders,
        SeeEmailLists,
        SeeOrderedProducts,
        EditShopTexts,
        ManageShop,
    ];

    fn roles(admin: bool, deliverer: bool, promoter: bool) -> Roles {
        Roles {
            admin,
            deliverer,
            promoter,
        }
    }

    fn allowed(roles: Roles) -> Vec<Permission> {
        ALL.into_iter().filter(|p| roles.can(*p)).collect()
    }

    /// As the IHP app's Test/Admin/RolesSpec
    #[test]
    fn each_role_may_do_its_part() {
        assert_eq!(allowed(roles(true, false, false)), ALL);
        assert_eq!(
            allowed(roles(false, true, false)),
            [SeeOrders, CreateOrders, MarkDelivered]
        );
        assert_eq!(
            allowed(roles(false, false, true)),
            [SeeOrders, SeeEmailLists, SeeOrderedProducts, EditShopTexts]
        );
        assert_eq!(
            allowed(roles(false, true, true)),
            [
                SeeOrders,
                CreateOrders,
                MarkDelivered,
                SeeEmailLists,
                SeeOrderedProducts,
                EditShopTexts
            ]
        );
        assert_eq!(allowed(roles(false, false, false)), []);
        assert!(!roles(false, false, false).any());
        assert!(roles(false, false, true).any());
    }
}
