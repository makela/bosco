module Admin.Controller.Customers where

import Admin.Controller.Orders (queryYears)
import Admin.Controller.Prelude
import Admin.View.Customers.Edit
import Admin.View.Customers.Email
import Admin.View.Customers.Index
import Admin.View.Customers.New
import Admin.View.Customers.Show

import Web.Controller.Orders (isEmail', nonEmptyOrWhitespace, setReverseName)

instance Controller CustomersController where
    beforeAction = ensureIsUser

    action CustomersAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (customersQ, pagination) <- query @Customer
            |> distinctOn #reverseName
            |> orderBy #reverseName
            |> paginate
        customers <- customersQ |> fetch
        render IndexView { .. }

    action NewCustomerAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        let customer = newRecord
        render NewView { .. }

    action ShowCustomerAction { customerId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        customer <- fetch customerId
        render ShowView { .. }

    action EditCustomerAction { customerId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        customer <- fetch customerId
        render EditView { .. }

    action UpdateCustomerAction { customerId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        customer <- fetch customerId
        customer
            |> buildCustomer
            |> ifValid \case
                Left customer -> render EditView { .. }
                Right customer -> do
                    customer <- customer |> updateRecord
                    setSuccessMessage "Customer updated"
                    redirectTo ShowCustomerAction { .. }

    action CreateCustomerAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        let customer = newRecord @Customer
        customer
            |> buildCustomer
            |> ifValid \case
                Left customer -> render NewView { .. }
                Right customer -> do
                    customer <- customer |> createRecord
                    setSuccessMessage "Customer created"
                    redirectTo $ ShowCustomerAction customer.id

    action DeleteCustomerAction { customerId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        customer <- fetch customerId
        orderCount <- query @Order |> filterWhere (#customerId, customerId) |> fetchCount
        when (orderCount > 0) do
            setErrorMessage ("Customer “" <> customer.name <> "” cannot be deleted because they have orders.")
            earlyReturn $ redirectTo EditCustomerAction { customerId }
        deleteRecord customer
        setSuccessMessage "Customer deleted"
        redirectTo CustomersAction

    action EmailsForDeliveryInfoAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (yearNow, years) <- queryYears
        let year = paramOrDefault @Integer yearNow "year"
        let dateAfter = ">= '" <> tshow year <> "-01-01 00:00:00'"
        let dateBefore = "< '" <> tshow (year + 1) <> "-01-01 00:00:00'"
        customers <- query @Order
            |> filterWhereSql (#cancelledAt, "IS NULL")
            |> filterWhereSql (#orderedAt, dateAfter)
            |> filterWhereSql (#orderedAt, dateBefore)
            |> fetch
            >>= collectionFetchRelated #customerId
        let emails = sort . nub $ map (toLower . (\x -> x.customerId.email)) customers
        render YearlyEmailView { .. }

    action EmailsForNewsLetterAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        customers <- query @Customer
            |> distinctOn #email
            |> fetch
        let emails = sort . nub $ map (toLower . (.email)) customers
        render EmailView { .. }

buildCustomer customer = customer
    |> fill @["name","email","phone","address"]
    |> validateField #name nonEmptyOrWhitespace
    |> validateField #email isEmail'
    |> validateField #phone isPhone
    |> validateField #address nonEmptyOrWhitespace
    |> setReverseName
