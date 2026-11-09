# Connect the owner-left check (about 2 minutes)

When someone leaves your organization, Vibernance hands each app they own to its sponsor, so apps don't sit ownerless. To know who has left, it needs to see **only whether each person is active**. This step gives your Vibernance identity exactly that, in your Google Admin console. A script can't do it for you: Google doesn't let scripts manage admin roles.

It's optional. Without it, your IT admins mark people as left in Vibernance themselves.

You need to be a **super admin** of your Google Workspace or Cloud Identity.

## Steps
1. Open **[admin.google.com › Account › Admin roles](https://admin.google.com/ac/roles)** and choose **Create new role**.
2. **Name:** `Vibernance directory read`. Description (optional): *Lets Vibernance see whether people are active, to hand apps to their sponsor when an owner leaves. Read-only.* Choose **Continue**.
3. Scroll past the **Admin console privileges** to **Admin API privileges**. Under **Users**, tick **Read**. Nothing else. Choose **Continue**, then **Create role**.
   - Make sure it's under *Admin API privileges*. The similar-looking option under *Admin console privileges* doesn't work for this.
4. On the new role's page, choose **Assign service accounts** (not *Assign users*) and enter your Vibernance identity, shown on the Vibernance setup page and by the setup script. It looks like `cust-yourorg@vibernance-customers-dev.iam.gserviceaccount.com`. Choose **Add**, then **Assign role**.

Then go back to the setup and press Enter, or in Vibernance open **Settings › Check directory now**. A new role can take a few minutes to start working.

## What Vibernance sees
For each person who uses Vibernance: active, suspended or deleted. Nothing else: no names it doesn't already have, no groups, no other users, and it can't change anything.

## Remove it
In **Admin roles**, open **Vibernance directory read** and choose **Delete role**. Vibernance then shows the check as not connected, and IT marks people as left by hand.
