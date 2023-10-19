module Admin.Controller.Products where

import Admin.Controller.Prelude
import Admin.View.Products.Edit
import Admin.View.Products.Index
import Admin.View.Products.New
import Admin.View.Products.Show

instance Controller ProductsController where
    beforeAction = ensureIsUser

    action ProductsAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (productsQ, pagination) <- query @Product
            |> paginate
        xs <- productsQ
            |> orderBy #ordering
            |> orderBy #name
            |> fetch
            >>= collectionFetchRelated #producerId
        let products = sortOn (\x -> x.producerId.name) xs
        render IndexView { .. }

    action NewProductAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        producers <- query @Producer |> fetch
        let product = newRecord
        render NewView { .. }

    action ShowProductAction { productId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        product <- fetch productId >>= fetchRelated #producerId
        render ShowView { .. }

    action EditProductAction { productId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        producers <- query @Producer |> fetch
        product <- fetch productId
        render EditView { .. }

    action UpdateProductAction { productId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        product <- fetch productId
        product
            |> buildProduct
            |> ifValid \case
                Left product -> do
                    producers <- query @Producer |> fetch
                    render EditView { .. }
                Right product -> do
                    product <- product |> updateRecord
                    setSuccessMessage "Product updated"
                    redirectTo ShowProductAction { .. }

    action CreateProductAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        let product = newRecord @Product
        product
            |> buildProduct
            |> ifValid \case
                Left product -> do
                    producers <- query @Producer |> fetch
                    render NewView { .. }
                Right product -> do
                    product <- product |> createRecord
                    setSuccessMessage "Product created"
                    redirectTo $ ShowProductAction product.id

    action DeleteProductAction { productId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        product <- fetch productId
        deleteRecord product
        setSuccessMessage "Product deleted"
        redirectTo ProductsAction

buildProduct product = product
    |> fill @["producerId","name","description","package","price","ordering","enabled"]
