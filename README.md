# Sentinel analytic rules + deploy templates

This repo hosts **custom Microsoft Sentinel Scheduled analytics rules** (YAML) and matching **ARM templates** (JSON) to support a one-click **Deploy to Azure** experience.

It exists primarily to provide a **public, anonymous-download location** for templates (required by the Azure portal deploy flow), even when the source rule development repo is private.

## Contents

- `analytic-rules/` — rule YAMLs (rule-as-code)
- `deploy/` — one ARM template per rule

## Deploy (Azure portal)

Open: [deploy/README.md](deploy/README.md)

## Deployment notes

- Deploy targets an **existing Log Analytics workspace** with Microsoft Sentinel enabled.
- You’ll be prompted for `workspaceName` and can toggle `enableRule`.
- For Azure US Government, use `https://portal.azure.us` instead of `https://portal.azure.com`.

## Maintainer

Maintained by a Microsoft Security Engineer **in a personal capacity**.

This is **not** an official Microsoft project and is **not** affiliated with, endorsed by, or supported by Microsoft.

## Disclaimer

All content is provided **“as is”**, without warranty of any kind (express or implied).

You are responsible for reviewing, testing, and validating these rules and templates before deploying them in any environment.

Microsoft is **not liable** for any damages or losses arising from the use of this repository.
