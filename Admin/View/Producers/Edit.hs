module Admin.View.Producers.Edit where
import Admin.View.Prelude
import Admin.View.Producers.New

data EditView = EditView { producer :: Producer }

instance View EditView where
    html EditView { .. } = [hsx|
        {breadcrumb}
        <h1>Edit Producer</h1>
        {renderForm producer}
    |]
        where
            breadcrumb = renderBreadcrumb
                [ breadcrumbLink "Producers" ProducersAction
                , breadcrumbText "Edit Producer"
                ]
