module Admin.View.Passwords.New where
import Admin.View.Prelude

data NewView = NewView

instance View NewView where
    html NewView = [hsx|
        <article>
            <form method="POST" action={UpdatePasswordAction}>
                <div class="flex flex-col my-6 space-y-2">
                    <label class="font-medium text-gray-700" for="oldPassword">Old password</label>
                    <input required type="password" id="oldPassword" name="oldPassword" />
                </div>
                <div class="flex flex-col my-6 space-y-2">
                    <label class="font-medium text-gray-700" for="newPassword">New password</label>
                    <input required type="password" id="newPassword" name="newPassword" />
                </div>
                <div class="flex flex-col my-6 space-y-2">
                    <label class="font-medium text-gray-700" for="confirmPassword">Confirm new password</label>
                    <input required type="password" id="confirmPassword" name="confirmPassword" />
                </div>
                <button class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded" type="submit">Update</button>
            </form>
        </article>
    |]
