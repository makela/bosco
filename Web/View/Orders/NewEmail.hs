module Web.View.Orders.NewEmail where
import Web.View.Prelude

data NewEmailView = NewEmailView { customer :: Customer }

instance View NewEmailView where
    html NewEmailView { .. } = [hsx|
            <h1>Tilaa uutiskirje</h1>
            <form method="POST" action={CreateEmailAction}>
                <div class="flex flex-col my-6 space-y-2" id="form-group-customer_name">
                    <label class="font-medium text-gray-700 " for="customer_name">Nimi</label>
                    <input type="text" name="name" placeholder="" id="customer_name" required="required" value={customer.name}
                           class={classes ["form-control", ("is-invalid", isInvalidName)]}>
                    {nameFeedback}
                </div>
                <div class="flex flex-col my-6 space-y-2" id="form-group-customer_email">
                    <label class="font-medium text-gray-700 " for="customer_email">Sähköposti</label>
                    <input type="text" name="email" placeholder="" id="customer_email" required="required" value={customer.email}
                           class={classes ["form-control", ("is-invalid", isInvalidEmail)]}>
                    {emailFeedback}
                </div>
                <input type="submit" value="Tilaa" />
            </form>
        |]
            where
                isInvalidName = isJust (getValidationFailure #name customer)
                isInvalidEmail = isJust (getValidationFailure #email customer)
                nameFeedback = case getValidationFailure #name customer of
                    Just result -> [hsx|<div class="invalid-feedback">{result}</div>|]
                    Nothing -> mempty
                emailFeedback = case getValidationFailure #email customer of
                    Just result -> [hsx|<div class="invalid-feedback">{result}</div>|]
                    Nothing -> mempty
