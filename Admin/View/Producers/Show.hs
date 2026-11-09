module Admin.View.Producers.Show where
import Admin.View.Prelude
import Web.View.Orders.Index (renderMarkdown)

import Admin.View.TextHistory (renderTextHistory)

data ShowView = ShowView
    { producer :: Producer
    , textChanges :: [Include "userId" TextChange]
    }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <p>{renderMarkdown producer.description}</p>
        {renderTextHistory textChanges}

    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Producers" ProducersAction
                , breadcrumbText [hsx|{producer.name}|]
                , breadcrumbLink "Edit" (EditProducerAction producer.id)
                ]
