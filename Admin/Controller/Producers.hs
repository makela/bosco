module Admin.Controller.Producers where

import Admin.Controller.Prelude
import Admin.View.Producers.Index
import Admin.View.Producers.New
import Admin.View.Producers.Edit
import Admin.View.Producers.Show

instance Controller ProducersController where
    beforeAction = ensureIsUser

    action ProducersAction = do
        (producersQ, pagination) <- query @Producer
            |> orderBy #name
            |> paginate
        producers <- producersQ |> fetch
        render IndexView { .. }

    action NewProducerAction = do
        let producer = newRecord
        render NewView { .. }

    action ShowProducerAction { producerId } = do
        producer <- fetch producerId
        render ShowView { .. }

    action EditProducerAction { producerId } = do
        producer <- fetch producerId
        render EditView { .. }

    action UpdateProducerAction { producerId } = do
        producer <- fetch producerId
        producer
            |> buildProducer
            |> ifValid \case
                Left producer -> render EditView { .. }
                Right producer -> do
                    producer <- producer |> updateRecord
                    setSuccessMessage "Producer updated"
                    redirectTo EditProducerAction { .. }

    action CreateProducerAction = do
        let producer = newRecord @Producer
        producer
            |> buildProducer
            |> ifValid \case
                Left producer -> render NewView { .. }
                Right producer -> do
                    producer <- producer |> createRecord
                    setSuccessMessage "Producer created"
                    redirectTo ProducersAction

    action DeleteProducerAction { producerId } = do
        producer <- fetch producerId
        deleteRecord producer
        setSuccessMessage "Producer deleted"
        redirectTo ProducersAction

buildProducer producer = producer
    |> fill @["name","subject","description"]
