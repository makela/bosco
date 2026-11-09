-- | A product's or producer's text history, newest first
module Admin.View.TextHistory (renderTextHistory) where

import Admin.View.Orders.Index (formatUTCTime)
import Admin.View.Prelude

renderTextHistory :: [Include "userId" TextChange] -> Html
renderTextHistory [] = [hsx|<p id="text-history">The texts haven't been changed here yet.</p>|]
renderTextHistory changes = [hsx|
    <div id="text-history">
        <h2>Text changes</h2>
        <ul>{forEach changes renderChange}</ul>
    </div>
|]

renderChange :: Include "userId" TextChange -> Html
renderChange change = [hsx|
    <li class="my-2">
        <p>{cs (formatUTCTime change.createdAt) :: Text}, {change.userId.email}: {change.fieldName}</p>
        <p class="whitespace-pre-line">Was: {orEmpty change.textBefore}</p>
        <p class="whitespace-pre-line">Now: {orEmpty change.textAfter}</p>
    </li>
|]
    where orEmpty text = if null text then "(empty)" else text
