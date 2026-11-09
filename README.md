# Vibernance setup for Google Cloud

Connects your Google Cloud to [Vibernance](https://vibernance.com), so Vibernance can deploy your organization's approved apps behind sign-in and keep watching them. You run it yourself, as an admin of your own organization. Vibernance never gets your admin rights, and you can take its access away with one command.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/Appcore-Solutions/vibernance-setup&cloudshell_tutorial=README.md)

## What it changes
Everything the script does happens in **one apps project** you choose or create. The optional directory role in the last row is a step you do yourself in the Admin console.

| What | Why |
| --- | --- |
| Turns on Cloud Run, IAP, Artifact Registry, Secret Manager | What the apps run on |
| An identity your apps run as (`vibernance-apps@…`), with no roles | Apps get only what's given to them |
| An image registry (`vibernance-apps`) | Images that passed Vibernance's security gate |
| **Your Vibernance identity** (`cust-…@vibernance-control-plane-dev.iam.gserviceaccount.com`) gets, in this project only: Cloud Run admin, IAP admin, act as the apps identity, push to the registry, write (not read) its own secrets, read Cloud Run metrics, read Cloud Run request logs through one log view | Deploy apps behind sign-in, check they're healthy and used, write secrets you enter without being able to read them back |
| A domain-restricted-sharing exception **on this project only**, allowing Appcore's Google customer ID (`C026oloip`) | New organizations only allow their own accounts in IAM |
| A storage bucket `<project>-vibernance-setup` | This setup's record, so you can re-run or remove it |
| **Directory (a 2-minute step in the Admin console; the script shows you how):** an admin role "Vibernance directory read" with only *Admin API › Users › Read*, assigned to your Vibernance identity. Optional | Vibernance sees only whether each person is active, to hand an app to its sponsor when its owner leaves |

It creates no keys and grants nothing outside the apps project. Vibernance can't read your apps' data, secrets or other projects.

## Run it
The easy way: on the Vibernance setup page, sign in, copy your setup code and choose **Open in Cloud Shell**. A guide opens beside the terminal and walks you through it. Or, in Cloud Shell:

```bash
./setup.sh
```

It asks for your setup code, offers your projects and billing accounts to choose from, shows what will change, and asks before changing anything. It takes about 5 minutes and tells Vibernance itself when it's done.

For scripting: `./setup.sh --code <setup code> --project <id>` (or `--create-project <id> --billing-account <id>`), and `--dry-run` to see the plan first.

You need: Organization Policy Administrator on your organization (the setup offers to grant it to you), Owner of the apps project (or Project Creator and a billing account), and super admin in your directory for the optional owner-left check ([guide](docs/directory-role.md)).

## Take Vibernance's access away
```bash
./setup.sh --project yourorg-vibernance-apps --identity cust-… --identity-id 1234567890 --remove
```
Removes every grant to your Vibernance identity, the log view and the domain-policy exception. If you added the directory role, delete it in the Admin console (Admin roles › Vibernance directory read › Delete role). Your apps, images, logs and the apps project stay. Then tell Appcore, so your organization is closed on their side.
