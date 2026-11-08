module Admin.View.Sessions.New where
import Admin.View.Prelude
import IHP.AuthSupport.View.Sessions.New

import Application.Demo (DemoLogin (..), demoLogins)

instance View (NewView User) where
    html NewView { .. } = [hsx|
        <div class="h-100" id="sessions-new">
            <div class="d-flex align-items-center">
                <div class="w-100">
                    <div style="max-width: 400px" class="mx-auto mb-5">
                        <h2>Please login</h2>
                        {when isDemo renderDemoLogins}
                        {renderForm user}
                    </div>
                </div>
            </div>
        </div>
    |]

renderForm :: User -> Html
renderForm user = [hsx|
    <form method="POST" action={CreateSessionAction}>
        <div class="form-group">
            <input name="email" value={user.email} type="email" class="form-control" placeholder="E-Mail" required="required" autofocus="autofocus" />
        </div>
        <div class="form-group">
            <input name="password" type="password" class="form-control" placeholder="Password"/>
        </div>
        <button type="submit" class="btn btn-primary btn-block">Login</button>
    </form>
|]

-- | On a demo, anyone can log in with one click as one of the demo's users
renderDemoLogins :: Html
renderDemoLogins = [hsx|
    <div class="demo-logins">
        <p>Try it without an account, as an admin or as a delivery person who only sees orders:</p>
        <div class="demo-login-buttons">{forEach demoLogins renderDemoLogin}</div>
    </div>
|]
  where
    renderDemoLogin demo = [hsx|
        <form method="POST" action={DemoLoginAction demo.role}>
            <button type="submit" class="demo-login">{demo.label}</button>
        </form>
    |]
