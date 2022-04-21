module Admin.View.Producers.Index where
import Admin.View.Prelude

data IndexView = IndexView { producers :: [Producer] , pagination :: Pagination }

instance View IndexView where
    html IndexView { .. } = [hsx|
        {breadcrumb}

        <h1>Index<a href={pathTo NewProducerAction} class="btn btn-primary ml-4">+ New</a></h1>
        <div class="table-responsive">
            <table class="table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Produces</th>
                        <th></th>
                        <th></th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach producers renderProducer}</tbody>
            </table>
            {renderPagination pagination}
        </div>
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Producers" ProducersAction
                ]

renderProducer :: Producer -> Html
renderProducer producer = [hsx|
    <tr>
        <td>{get #name producer}</td>
        <td>{get #subject producer}</td>
        <td><a href={ShowProducerAction (get #id producer)}>Show</a></td>
        <td><a href={EditProducerAction (get #id producer)} class="text-muted">Edit</a></td>
        <td><a href={DeleteProducerAction (get #id producer)} class="js-delete text-muted">Delete</a></td>
    </tr>
|]
