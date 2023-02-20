module Admin.View.WelcomeMessages.Index where
import Admin.View.Prelude

data IndexView = IndexView { welcomeMessages :: [WelcomeMessage] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Published</th>
                    </tr>
                </thead>
                <tbody>{forEach welcomeMessages renderWelcomeMessage}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText [hsx|<span>Welcome Messages</span>|]
                , breadcrumbLink "New" NewWelcomeMessageAction
                ]

renderWelcomeMessage :: WelcomeMessage -> Html
renderWelcomeMessage welcomeMessage = [hsx|
    <tr>
        <td><a href={ShowWelcomeMessageAction welcomeMessage.id}>{timeAgo welcomeMessage.publishedAt}</a></td>
    </tr>
|]
