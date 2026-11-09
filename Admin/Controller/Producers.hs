module Admin.Controller.Producers where

import Admin.Controller.Prelude
import Admin.View.Producers.Index
import Admin.View.Producers.New
import Admin.View.Producers.Edit
import Admin.View.Producers.Show

instance Controller ProducersController where
    beforeAction = ensureIsUser

    action ProducersAction = do
        _ <- requirePermission ManageShop
        (producersQ, pagination) <- query @Producer
            |> orderBy #name
            |> paginate
        producers <- producersQ |> fetch
        render IndexView { .. }

    action NewProducerAction = do
        _ <- requirePermission ManageShop
        let producer = newRecord
        render NewView { .. }

    action ShowProducerAction { producerId } = do
        _ <- requirePermission ManageShop
        producer <- fetch producerId
        render ShowView { .. }

    action EditProducerAction { producerId } = do
        _ <- requirePermission ManageShop
        producer <- fetch producerId
        render EditView { .. }

    action UpdateProducerAction { producerId } = do
        _ <- requirePermission ManageShop
        producer <- fetch producerId
        producer
            |> buildProducer
            |> ifValid \case
                Left producer -> render EditView { .. }
                Right producer -> do
                    producer <- producer |> updateRecord
                    setSuccessMessage "Producer updated"
                    redirectTo ShowProducerAction { .. }

    action CreateProducerAction = do
        _ <- requirePermission ManageShop
        let producer = newRecord @Producer
        producer
            |> buildProducer
            |> ifValid \case
                Left producer -> render NewView { .. }
                Right producer -> do
                    producer <- producer |> createRecord
                    setSuccessMessage "Producer created"
                    redirectTo $ ShowProducerAction producer.id

    action DeleteProducerAction { producerId } = do
        _ <- requirePermission ManageShop
        producer <- fetch producerId
        productCount <- query @Product |> filterWhere (#producerId, producerId) |> fetchCount
        when (productCount > 0) do
            setErrorMessage ("Producer “" <> producer.name <> "” cannot be deleted because it has products. Delete its products first, or disable the producer instead.")
            earlyReturn $ redirectTo EditProducerAction { producerId }
        deleteRecord producer
        setSuccessMessage "Producer deleted"
        redirectTo ProducersAction

buildProducer producer = producer
    |> fill @["name","subject","description","enabled"]
