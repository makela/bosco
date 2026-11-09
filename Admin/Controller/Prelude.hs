module Admin.Controller.Prelude
( module Admin.Types
, module Application.Helper.Controller
, module Application.Permission
, module IHP.ControllerPrelude
, module Generated.Types
, requirePermission
)
where

import Admin.Types
import Application.Helper.Controller
import Application.Permission
import IHP.ControllerPrelude
import Generated.Types
import Admin.Routes

-- | The logged-in user, when they may do this; access denied otherwise
requirePermission :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Permission -> IO User
requirePermission permission = do
    user <- fetch currentUserId
    accessDeniedUnless (can user permission)
    pure user
