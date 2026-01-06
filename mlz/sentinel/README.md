# Mission Landing Zone (MLZ) Sentinel Package

This subtree houses the code, configuration, and documentation that adapts the Sentinel accelerator for Mission Landing Zone environments. Use it to stage changes before upstreaming them into Mission LZ or before packaging for deployment via the MLZ automation.

## Directory layout

- `infrastructure/` – Bicep files, parameters, and deployment artifacts that provision Sentinel resources when run inside an MLZ subscription.
- `automation/` – Scripts and tooling used to bootstrap analytics, enable data connectors, or run post-provisioning steps for MLZ.
- `content/` – MLZ-focused analytics, hunting queries, metadata, playbooks, and workbooks. Populate these folders as you curate Sentinel content for MLZ tenants.
- `docs/` – References, runbooks, and integration notes that explain how to consume this subtree inside Mission LZ.
- `tests/` – Validation harnesses (Pester tests, pipeline definitions, sample datasets) that verify the MLZ build-out.

The files in the repository root remain the authoritative source for the baseline Sentinel accelerator. Copy, import, or link only the assets required for MLZ so the two code paths stay isolated.
