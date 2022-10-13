module Admin.View.Producers.Show where
import Admin.View.Prelude
import Web.View.Orders.Index (renderMarkdown)

data ShowView = ShowView { producer :: Producer }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <p>{renderMarkdown producer.description}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Producers" ProducersAction
                , breadcrumbText [hsx|{producer.name}|]
                , breadcrumbLink "Edit" (EditProducerAction producer.id)
                ]
