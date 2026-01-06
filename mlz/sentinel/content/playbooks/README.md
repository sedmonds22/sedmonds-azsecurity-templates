# Playbooks (MLZ)

Add Logic App or Power Automate definitions that support the MLZ Sentinel deployment. Group them by response scenario, and document dependencies (managed identities, connectors) within each workflow file.

> **Authorization reminder:** After deploying these playbooks, open each generated API connection (Azure AD, Microsoft Sentinel, Office 365, etc.) in the Azure portal and authorize them with the appropriate credentials. The templates intentionally leave connections unauthenticated so operators can grant consent in the target tenant before running automation.
