module Admin.Controller.Products where

import Admin.Controller.Prelude
import Admin.View.Products.Index
import Admin.View.Products.New
import Admin.View.Products.Edit
import Admin.View.Products.Show

instance Controller ProductsController where
    beforeAction = ensureIsUser

    action ProductsAction = do
        (productsQ, pagination) <- query @Product
            |> paginate
        products <- productsQ
            |> orderBy #name
            |> fetch
            >>= collectionFetchRelated #producerId
        render IndexView { .. }

    action NewProductAction = do
        producers <- query @Producer |> fetch
        let product = newRecord
        render NewView { .. }

    action ShowProductAction { productId } = do
        product <- fetch productId >>= fetchRelated #producerId
        render ShowView { .. }

    action EditProductAction { productId } = do
        producers <- query @Producer |> fetch
        product <- fetch productId
        render EditView { .. }

    action UpdateProductAction { productId } = do
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
                    redirectTo EditProductAction { .. }

    action CreateProductAction = do
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
                    redirectTo ProductsAction

    action DeleteProductAction { productId } = do
        product <- fetch productId
        deleteRecord product
        setSuccessMessage "Product deleted"
        redirectTo ProductsAction

buildProduct product = product
    |> fill @["producerId","name","description","package","price"]
