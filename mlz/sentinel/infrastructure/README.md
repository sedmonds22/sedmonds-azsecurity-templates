# MLZ Sentinel Infrastructure

Place Mission Landing Zone–specific infrastructure as code here. Current layout:

- `bicep/main.bicep` – Subscription-scoped entry point that reuses the baseline modules but applies MLZ defaults (tags, diagnostics, UEBA).
- `bicep/parameters/mission-dev.bicepparam` – Development parameter file wired to MLZ naming and diagnostic settings.
- `bicep/` – MLZ-flavoured Bicep templates, parameters, and modules. Keep MLZ-specific defaults separate from the baseline `bicep/` directory.
- `pipelines/` – (Optional) Azure DevOps or GitHub workflow definitions that deploy Sentinel within MLZ subscriptions.

When you import existing templates from the root `bicep/` directory, copy them into this folder and adjust the parameters/outputs so they align with Mission LZ guardrails. Document any deltas in this README so downstream consumers know why the MLZ version differs from the baseline.
