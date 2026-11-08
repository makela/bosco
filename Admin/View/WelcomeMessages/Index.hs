module Admin.View.WelcomeMessages.Index where
import Admin.View.Prelude

import Admin.View.CheckMark (isEnabled)

data IndexView = IndexView { welcomeMessages :: [WelcomeMessage] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Published</th>
                        <th>Is Ordering Enabled</th>
                    </tr>
                </thead>
                <tbody>{forEach welcomeMessages renderWelcomeMessage}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            -- A demo's welcome text is fixed, see the controller
            breadcrumb = renderBreadcrumb $
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText [hsx|<span>Welcome Messages</span>|]
                ]
                <> [breadcrumbLink "New" NewWelcomeMessageAction | not isDemo]

renderWelcomeMessage :: WelcomeMessage -> Html
renderWelcomeMessage welcomeMessage = [hsx|
    <tr>
        <td><a href={ShowWelcomeMessageAction welcomeMessage.id}>{timeAgo welcomeMessage.publishedAt}</a></td>
        <td>{isEnabled welcomeMessage.isOrderingEnabled}</td>
    </tr>
|]
