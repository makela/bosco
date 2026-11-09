module Admin.Controller.PaymentInstructions where

import Admin.Controller.Prelude
import Admin.View.PaymentInstructions.Index
import Admin.View.PaymentInstructions.New
import Admin.View.PaymentInstructions.Edit
import Admin.View.PaymentInstructions.Show
import Application.Demo (isDemo)

instance Controller PaymentInstructionsController where
    beforeAction = ensureIsUser

    action PaymentInstructionsAction = do
        _ <- requirePermission ManageShop
        (paymentInstructionsQ, pagination) <- query @PaymentInstruction |> paginate
        paymentInstructions <- paymentInstructionsQ |> fetch
        render IndexView { .. }

    action NewPaymentInstructionAction = do
        _ <- requirePermission ManageShop
        refuseOnDemo
        let paymentInstruction = newRecord
        render NewView { .. }

    action ShowPaymentInstructionAction { paymentInstructionId } = do
        _ <- requirePermission ManageShop
        paymentInstruction <- fetch paymentInstructionId
        render ShowView { .. }

    action EditPaymentInstructionAction { paymentInstructionId } = do
        _ <- requirePermission ManageShop
        refuseOnDemo
        paymentInstruction <- fetch paymentInstructionId
        render EditView { .. }

    action UpdatePaymentInstructionAction { paymentInstructionId } = do
        _ <- requirePermission ManageShop
        refuseOnDemo
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
        _ <- requirePermission ManageShop
        refuseOnDemo
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
        _ <- requirePermission ManageShop
        refuseOnDemo
        paymentInstruction <- fetch paymentInstructionId
        deleteRecord paymentInstruction
        setSuccessMessage "PaymentInstruction deleted"
        redirectTo PaymentInstructionsAction

buildPaymentInstruction paymentInstruction = paymentInstruction
    |> fill @'["text"]

-- | A demo's invoices always show its fake payment details, so changing the
-- stored ones would do nothing but let a visitor put a real account here
refuseOnDemo :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
refuseOnDemo = when isDemo do
    setErrorMessage "The demo's payment details are fixed and can't be changed"
    earlyReturn (redirectTo PaymentInstructionsAction)
