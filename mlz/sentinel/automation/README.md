# MLZ Sentinel Automation

Use this directory for scripts and tooling that configure Sentinel inside Mission Landing Zone deployments.

- `scripts/` – PowerShell, CLI, or Python automation that deploys content, turns on data connectors, or tunes Sentinel settings for MLZ tenants.
- `modules/` – Reusable script modules or helper libraries shared by the automation.
- `tools/` – Optional binaries or configuration files required by the automation workflow.

When porting scripts from the root `scripts/` folder, copy them here and adjust defaults (workspace names, parameter files, identity requirements) so they comply with MLZ standards.

## Current assets

- `scripts/Deploy-MLZInfrastructure.ps1` – Wraps the MLZ Bicep entry point and parameter file so operators can deploy the MLZ Sentinel workspace with a single command.
