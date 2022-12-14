module Admin.Controller.Static where
import Admin.Controller.Prelude
import Admin.View.Static.Welcome

instance Controller StaticController where
    beforeAction = ensureIsUser

    action WelcomeAction = do
        user <- fetch currentUserId
        render WelcomeView { .. }
