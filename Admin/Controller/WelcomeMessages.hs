module Admin.Controller.WelcomeMessages where

import Admin.Controller.Prelude
import Admin.View.WelcomeMessages.Edit
import Admin.View.WelcomeMessages.Index
import Admin.View.WelcomeMessages.New
import Admin.View.WelcomeMessages.Show

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
        welcomeMessage <- fetch welcomeMessageId
        deleteRecord welcomeMessage
        setSuccessMessage "WelcomeMessage deleted"
        redirectTo WelcomeMessagesAction

buildWelcomeMessage welcomeMessage = welcomeMessage
    |> fill @["text","isOrderingEnabled"]
