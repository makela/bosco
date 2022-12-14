module Admin.Controller.PaymentInstructions where

import Admin.Controller.Prelude
import Admin.View.PaymentInstructions.Index
import Admin.View.PaymentInstructions.New
import Admin.View.PaymentInstructions.Edit
import Admin.View.PaymentInstructions.Show

instance Controller PaymentInstructionsController where
    beforeAction = ensureIsUser

    action PaymentInstructionsAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (paymentInstructionsQ, pagination) <- query @PaymentInstruction |> paginate
        paymentInstructions <- paymentInstructionsQ |> fetch
        render IndexView { .. }

    action NewPaymentInstructionAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        let paymentInstruction = newRecord
        render NewView { .. }

    action ShowPaymentInstructionAction { paymentInstructionId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        paymentInstruction <- fetch paymentInstructionId
        render ShowView { .. }

    action EditPaymentInstructionAction { paymentInstructionId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        paymentInstruction <- fetch paymentInstructionId
        render EditView { .. }

    action UpdatePaymentInstructionAction { paymentInstructionId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        paymentInstruction <- fetch paymentInstructionId
        paymentInstruction
            |> buildPaymentInstruction
            |> ifValid \case
                Left paymentInstruction -> render EditView { .. }
                Right paymentInstruction -> do
                    paymentInstruction <- paymentInstruction |> updateRecord
                    setSuccessMessage "PaymentInstruction updated"
                    redirectTo ShowPaymentInstructionAction { .. }

    action CreatePaymentInstructionAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        let paymentInstruction = newRecord @PaymentInstruction
        paymentInstruction
            |> buildPaymentInstruction
            |> ifValid \case
                Left paymentInstruction -> render NewView { .. }
                Right paymentInstruction -> do
                    paymentInstruction <- paymentInstruction |> createRecord
                    setSuccessMessage "PaymentInstruction created"
                    redirectTo $ ShowPaymentInstructionAction paymentInstruction.id

    action DeletePaymentInstructionAction { paymentInstructionId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        paymentInstruction <- fetch paymentInstructionId
        deleteRecord paymentInstruction
        setSuccessMessage "PaymentInstruction deleted"
        redirectTo PaymentInstructionsAction

buildPaymentInstruction paymentInstruction = paymentInstruction
    |> fill @'["text"]
