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
        <td>{welcomeMessage.text}</td>
        <td>{timeAgo welcomeMessage.publishedAt}</td>
        <td><a href={ShowWelcomeMessageAction welcomeMessage.id}>Show</a></td>
        <td><a href={EditWelcomeMessageAction welcomeMessage.id} class="text-muted">Edit</a></td>
        <td><a href={DeleteWelcomeMessageAction welcomeMessage.id} class="js-delete text-muted">Delete</a></td>
    </tr>
|]
