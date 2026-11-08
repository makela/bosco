module Admin.Controller.Sessions where

import Admin.Controller.Prelude
import Admin.View.Sessions.New
import Application.Demo
import qualified IHP.AuthSupport.Controller.Sessions as Sessions

instance Controller SessionsController where
    action NewSessionAction = Sessions.newSessionAction @User
    action CreateSessionAction = Sessions.createSessionAction @User
    action DeleteSessionAction = Sessions.deleteSessionAction @User
    action DemoLoginAction { role } = case (isDemo, demoLogin role) of
        (True, Just demo) -> do
            user <- ensureDemoUser demo
            login user
            redirectTo WelcomeAction
        _ -> renderNotFound

instance Sessions.SessionsControllerConfig User
