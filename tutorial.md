# Set up Vibernance

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

Connect your organization's Google Cloud to Vibernance. Everything runs here, in your own account, as you. Vibernance never gets your admin rights, and you can disconnect it with one command.

You'll need the **setup code** from the Vibernance setup page. It works once, for 1 hour.

Choose **Start** to begin.

## Run the setup

Click the button on the command below to put it in the terminal, then press **Enter** there.

```sh
./setup.sh
```

The setup asks you three things:

1. **Your setup code**, from the Vibernance setup page.
2. **Which project** Vibernance deploys your apps into. A new, empty project is best: Vibernance gets roles in that project only.
3. **Continue?** after a summary of what will change. Nothing changes before you say yes.

It then takes about 5 minutes. When it says **✓ Connected**, choose **Next**.

If it stops, it says why and what to do. Running the same command again picks up where it stopped.

## The owner-left check (optional, 2 minutes)

When someone leaves, Vibernance hands each app they own to its sponsor. To know who has left, it needs to see only **whether each person is active**. Google doesn't let scripts do this step, so it's done in your Admin console:

1. Open **[admin.google.com › Admin roles](https://admin.google.com/ac/roles)** and choose **Create new role**.
2. **Name:** `Vibernance directory read`
3. Under **Admin API privileges** (not *Admin console privileges*), tick **Users › Read**. Nothing else. Create the role.
4. On the new role, choose **Assign service accounts** and paste your **Vibernance identity**. The setup printed it; it starts with `cust-`. Copy it from the terminal rather than typing it.

Back in the terminal, press **Enter**. The setup asks Vibernance to check it and shows the result. A new role can take a few minutes; you can also check later in Vibernance under **Settings › Check directory now**.

Prefer not to? Type **s** in the terminal instead. Your IT admins can mark people as left in Vibernance.

[The full guide](https://github.com/Appcore-Solutions/vibernance-setup/blob/main/docs/directory-role.md)

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Your organization is connected. Go back to the Vibernance setup page, or open Vibernance and sign in: you're your organization's first IT admin.

Next, in Vibernance:

* **Install the GitHub App** on the repositories you want to submit, from Vibernance's **Submit an app** page.
* **Add people:** anyone in your organization can sign in; IT admins give roles on the **People** page.

**To disconnect later**, run the command the setup printed at the end (`./setup.sh … --remove`). It removes every grant Vibernance has; your apps keep running.
