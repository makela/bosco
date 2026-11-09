module Admin.Controller.Products where

import Admin.Controller.Prelude
import Web.Controller.Orders (productOrder, sortProducers)
import Admin.View.Products.Edit
import Admin.View.Products.Index
import Admin.View.Products.New
import Admin.View.Products.Show

instance Controller ProductsController where
    beforeAction = ensureIsUser

    action ProductsAction = do
        _ <- requirePermission ManageShop
        -- The whole catalog on one page, grouped by producer in the order
        -- the order form uses
        producers <- query @Producer |> fetch
        xs <- query @Product |> fetch >>= collectionFetchRelated #producerId
        let producerRank = zip (map (.id) (sortProducers producers)) [0 :: Int ..]
            rank x = lookup x.producerId.id producerRank
            products = sortOn (\x -> (rank x, productOrder x)) xs
        render IndexView { .. }

    action NewProductAction = do
        _ <- requirePermission ManageShop
        producers <- query @Producer |> fetch
        let product = newRecord
        render NewView { .. }

    action ShowProductAction { productId } = do
        _ <- requirePermission ManageShop
        product <- fetch productId >>= fetchRelated #producerId
        render ShowView { .. }

    action EditProductAction { productId } = do
        _ <- requirePermission ManageShop
        producers <- query @Producer |> fetch
        product <- fetch productId
        render EditView { .. }

    action UpdateProductAction { productId } = do
        _ <- requirePermission ManageShop
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
        _ <- requirePermission ManageShop
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
        _ <- requirePermission ManageShop
        product <- fetch productId
        -- Ordered products are part of past orders, so they can only be disabled
        timesOrdered <- query @OrderedProduct |> filterWhere (#productId, productId) |> fetchCount
        when (timesOrdered > 0) do
            setErrorMessage ("Product “" <> product.name <> "” cannot be deleted because it has been ordered. Disable it instead.")
            earlyReturn $ redirectTo EditProductAction { productId }
        deleteRecord product
        setSuccessMessage "Product deleted"
        redirectTo ProductsAction

buildProduct product = product
    |> fill @["producerId","name","description","package","price","ordering","enabled"]
