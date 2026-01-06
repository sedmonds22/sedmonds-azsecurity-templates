# MLZ Sentinel Bicep Artifacts

Store the Mission Landing Zone variants of Sentinel Bicep templates in this folder. Suggested layout:

- `main.bicep` – Entry point that orchestrates the MLZ Sentinel deployment.
- `modules/` – Supporting Bicep modules tailored for MLZ constraints (naming, tagging, policy compliance).
- `parameters/` – Environment-specific parameter files (development, staging, production) for MLZ subscriptions.

Copy the baseline templates from the repositorys `bicep/` directory when you need a starting point. Update them in-place here so MLZ integrations stay isolated from the independent Sentinel accelerator.
