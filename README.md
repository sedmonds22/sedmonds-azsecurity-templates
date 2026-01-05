# Sentinel analytic rules + deploy templates

This repo contains **custom Microsoft Sentinel Scheduled analytics rules** (YAML) and matching **ARM templates** (JSON) so you can use a one-click **Deploy to Azure** experience.

## Contents

- `analytic-rules/` — rule YAMLs (rule-as-code)
- `deploy/` — one ARM template per rule

## Deploy (Azure portal)

Open: [deploy/README.md](deploy/README.md)

## Notes

- Deploy targets an **existing Log Analytics workspace** with Microsoft Sentinel enabled.
- You’ll be prompted for `workspaceName` and can toggle `enableRule`.
- For Azure US Government, use `https://portal.azure.us` instead of `https://portal.azure.com`.
