module Web.Worker where

import Generated.Types
import IHP.Job.Runner
import IHP.Job.Types
import IHP.Prelude
import Web.Types

import Web.Job.EmailOrder

instance Worker WebApplication where
    workers _ =
        [ worker @EmailOrderJob
        -- Generator Marker
        ]
