module Admin.View.CheckMark where
import Admin.View.Prelude

isEnabled :: Bool -> Text
isEnabled True = "✓"
isEnabled _    = ""
