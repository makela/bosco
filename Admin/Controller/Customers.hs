module Admin.Controller.Customers where

import Admin.Controller.Prelude
import Admin.View.Customers.Index
import Admin.View.Customers.New
import Admin.View.Customers.Edit
import Admin.View.Customers.Show
import Admin.View.Customers.Email

import Web.Controller.Orders (isEmail', isPhone)

instance Controller CustomersController where
    beforeAction = ensureIsUser

    action CustomersAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (customersQ, pagination) <- query @Customer
            |> orderBy #name
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
        deleteRecord customer
        setSuccessMessage "Customer deleted"
        redirectTo CustomersAction

    action EmailsForDeliveryInfoAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        customers <- query @Order
            |> filterWhereSql (#cancelledAt, "IS NULL")
            |> fetch
            >>= collectionFetchRelated #customerId
        let emails = sort . nub $ map (\x -> x.customerId.email) customers
        render EmailView { .. }

    action EmailsForNewsLetterAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        customers <- query @Customer
            |> distinctOn #email
            |> fetch
        let emails = sort . nub $ map (\x -> x.email) customers
        render EmailView { .. }

buildCustomer customer = customer
    |> fill @["name","email","phone","address"]
    |> validateField #email isEmail'
    |> validateField #phone isPhone
    |> validateField #address nonEmpty
