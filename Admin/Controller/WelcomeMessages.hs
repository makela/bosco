module Admin.Controller.WelcomeMessages where

import Admin.Controller.Prelude
import Admin.View.WelcomeMessages.Edit
import Admin.View.WelcomeMessages.Index
import Admin.View.WelcomeMessages.New
import Admin.View.WelcomeMessages.Show
import Application.Demo (isDemo)

instance Controller WelcomeMessagesController where
    beforeAction = ensureIsUser

    action WelcomeMessagesAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        (welcomeMessagesQ, pagination) <- query @WelcomeMessage |> orderByDesc #publishedAt |> paginate
        welcomeMessages <- welcomeMessagesQ |> fetch
        render IndexView { .. }

    action NewWelcomeMessageAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        refuseOnDemo
        let welcomeMessage = newRecord |> set #isOrderingEnabled True
        render NewView { .. }

    action ShowWelcomeMessageAction { welcomeMessageId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        welcomeMessage <- fetch welcomeMessageId
        render ShowView { .. }

    action EditWelcomeMessageAction { welcomeMessageId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        welcomeMessage <- fetch welcomeMessageId
        render EditView { .. }

    action UpdateWelcomeMessageAction { welcomeMessageId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        welcomeMessage <- fetch welcomeMessageId
        welcomeMessage
            |> buildWelcomeMessage
            |> ifValid \case
                Left welcomeMessage -> render EditView { .. }
                Right welcomeMessage -> do
                    welcomeMessage <- welcomeMessage |> updateRecord
                    setSuccessMessage "WelcomeMessage updated"
                    redirectTo ShowWelcomeMessageAction { .. }

    action CreateWelcomeMessageAction = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        refuseOnDemo
        let welcomeMessage = newRecord @WelcomeMessage
        welcomeMessage
            |> buildWelcomeMessage
            |> ifValid \case
                Left welcomeMessage -> render NewView { .. }
                Right welcomeMessage -> do
                    welcomeMessage <- welcomeMessage |> createRecord
                    setSuccessMessage "WelcomeMessage created"
                    redirectTo $ ShowWelcomeMessageAction welcomeMessage.id

    action DeleteWelcomeMessageAction { welcomeMessageId } = do
        user <- fetch currentUserId
        accessDeniedUnless user.isAdmin
        refuseOnDemo
        welcomeMessage <- fetch welcomeMessageId
        deleteRecord welcomeMessage
        setSuccessMessage "WelcomeMessage deleted"
        redirectTo WelcomeMessagesAction

-- | On a demo only ordering can be opened and closed: the text is shown to
-- everyone on the order page, so a visitor could put e.g. their own bank
-- account there
buildWelcomeMessage welcomeMessage
    | isDemo = welcomeMessage |> fill @'["isOrderingEnabled"]
    | otherwise = welcomeMessage |> fill @["text","isOrderingEnabled"]

refuseOnDemo :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IO ()
refuseOnDemo = when isDemo do
    setErrorMessage "The demo's welcome message is fixed: you can open and close ordering, but not change the text"
    earlyReturn (redirectTo WelcomeMessagesAction)
