# Automation Scripts for MLZ Sentinel

Drop script entry points here. Group them by scenario (infrastructure deployment, content publishing, connector enablement) or by pipeline stage. Aim to keep parameter sets and output artifacts aligned with Mission Landing Zone requirements so that CI/CD systems can run them without additional wrapping.

When you import a script from the root `scripts/` directory, document any deviations in comments at the top of the file and update this README with guidance on when to use the MLZ versus baseline variant.

## Sentinel automation identity requirements

`Deploy-MLZInfrastructure.ps1` now provisions a user-assigned managed identity (`uai-sentinel-automation-<hash>`) so the underlying Bicep template can discover the **Azure Security Insights** service principal and grant it the *Microsoft Sentinel Automation Contributor* role on the workspace resource group. The template automatically assigns **User Access Administrator** on that resource group to the identity so it can create RBAC bindings, but you (or another global admin) must pre-authorize the identity in Microsoft Entra ID with directory-level permissions that allow calling `az ad sp list` (for example, the *Security Administrator* role). Without those directory permissions, the deployment script will fail while attempting to look up the Azure Security Insights principal.
