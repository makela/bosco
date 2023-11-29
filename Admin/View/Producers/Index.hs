module Admin.View.Producers.Index where
import Admin.View.Prelude

import Admin.View.CheckMark (isEnabled)

data IndexView = IndexView { producers :: [Producer] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Enabled</th>
                    </tr>
                </thead>
                <tbody>{forEach producers renderProducer}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbText [hsx|<span>Producers</span>|]
                , breadcrumbLink "New" NewProducerAction
                ]

renderProducer :: Producer -> Html
renderProducer producer = [hsx|
    <tr>
        <td><a href={ShowProducerAction producer.id}>{producer.name}</a></td>
        <td>{isEnabled producer.enabled}</td>
    </tr>
|]
