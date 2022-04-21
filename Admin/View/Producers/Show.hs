module Admin.View.Producers.Show where
import Admin.View.Prelude

data ShowView = ShowView { producer :: Producer }

instance View ShowView where
    html ShowView { .. } = [hsx|
        {breadcrumb}
        <h1>Show Producer</h1>
        <p>{producer}</p>

    |]
        where
            breadcrumb = renderBreadcrumb
                            [ breadcrumbLink "Producers" ProducersAction
                            , breadcrumbText "Show Producer"
                            ]