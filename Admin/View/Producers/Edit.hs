module Admin.View.Producers.Edit where
import Admin.View.Prelude
import Admin.View.Producers.New

data EditView = EditView { producer :: Producer }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        {renderForm producer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Home" WelcomeAction
                , breadcrumbLink "Producers" ProducersAction
                , breadcrumbLink [hsx|{producer.name}|] (ShowProducerAction producer.id)
                , breadcrumbText "Edit"
                , breadcrumbLink [hsx|<a href={DeleteProducerAction producer.id} class="js-delete back-button">Delete</a>|] (DeleteProducerAction producer.id)
                ]
