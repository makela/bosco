module WorkerMain () where

import IHP.Prelude
import IHP.FrameworkConfig (RootApplication (..))
import IHP.Job.Types (Worker (..))
import Web.Types (WebApplication (..))
import Web.Worker ()

instance Worker RootApplication where
    workers _ =
        workers WebApplication
        -- Generator Marker
