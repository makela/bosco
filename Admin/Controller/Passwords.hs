module Admin.Controller.Passwords where

import Admin.Controller.Prelude
import Admin.View.Passwords.New
import Application.Demo (isDemoUser)
import Data.Password.Bcrypt (mkPassword)
import Data.Password.Validate

instance Controller PasswordsController where
    beforeAction = do
        ensureIsUser
        -- Everyone shares the demo's logins, so one visitor must not lock
        -- the others out by changing the password
        when (maybe False isDemoUser currentUserOrNothing) do
            setErrorMessage "The demo logins' passwords can't be changed"
            earlyReturn (redirectTo WelcomeAction)

    action NewPasswordAction = do
        render NewView

    action UpdatePasswordAction = do
        case currentUserOrNothing of
            Just currentUser -> do
                let oldPassword = paramOrDefault @Text "" "oldPassword"
                    newPassword = paramOrDefault @Text "" "newPassword"
                    confirmPassword = paramOrDefault @Text "" "confirmPassword"
                if verifyPassword currentUser oldPassword &&
                    newPassword == confirmPassword &&
                    isValidPassword defaultPasswordPolicy_ (mkPassword newPassword)
                then do
                    hashedNewPassword <- hashPassword newPassword
                    _ <- currentUser
                        |> set #passwordHash hashedNewPassword
                        |> updateRecord
                    setSuccessMessage "Password updated"
                    redirectTo WelcomeAction
                else do
                    setErrorMessage "Passwords do not meet the requirements"
                    redirectTo NewPasswordAction
            Nothing -> renderPlain "Please login first"
