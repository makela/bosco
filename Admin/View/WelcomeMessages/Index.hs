module Admin.View.WelcomeMessages.Index where
import Admin.View.Prelude

data IndexView = IndexView { welcomeMessages :: [WelcomeMessage] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <a href={pathTo NewWelcomeMessageAction}>+ New</a>
        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Message</th>
                        <th>Published</th>
                        <th></th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach welcomeMessages renderWelcomeMessage}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "WelcomeMessages" WelcomeMessagesAction
                ]

renderWelcomeMessage :: WelcomeMessage -> Html
renderWelcomeMessage welcomeMessage = [hsx|
    <tr>
        <td>{get #text welcomeMessage}</td>
        <td>{get #publishedAt welcomeMessage}</td>
        <td><a href={ShowWelcomeMessageAction (get #id welcomeMessage)}>Show</a></td>
        <td><a href={EditWelcomeMessageAction (get #id welcomeMessage)} class="text-muted">Edit</a></td>
        <td><a href={DeleteWelcomeMessageAction (get #id welcomeMessage)} class="js-delete text-muted">Delete</a></td>
    </tr>
|]
