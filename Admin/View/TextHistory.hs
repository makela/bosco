-- | A product's or producer's text history, newest first. One quiet line
-- per change; the texts, a description can be long, open by clicking it.
module Admin.View.TextHistory (renderTextHistory) where

import Admin.View.Orders.Index (formatUTCTime)
import Admin.View.Prelude

renderTextHistory :: [Include "userId" TextChange] -> Html
renderTextHistory [] = [hsx|<p id="text-history" class="mt-8 text-sm text-gray-500">The texts haven't been changed here yet.</p>|]
renderTextHistory changes = [hsx|
    <div id="text-history" class="mt-8 text-sm text-gray-600">
        <h2 class="text-base font-medium">Text changes</h2>
        {forEach changes renderChange}
    </div>
|]

renderChange :: Include "userId" TextChange -> Html
renderChange change = [hsx|
    <details class="my-1">
        <summary class="cursor-pointer">{cs (formatUTCTime change.createdAt) :: Text} · {change.userId.email} · {change.fieldName}</summary>
        <div class="ml-4 my-2 pl-3 border-l-2 border-gray-200 space-y-2">
            <p class="whitespace-pre-line">Was: {orEmpty change.textBefore}</p>
            <p class="whitespace-pre-line">Now: {orEmpty change.textAfter}</p>
        </div>
    </details>
|]
    where orEmpty text = if null text then "(empty)" else text
