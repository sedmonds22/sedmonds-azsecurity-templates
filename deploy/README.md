# Deploy to Azure (one per rule)

Each button deploys one Microsoft Sentinel **Scheduled** analytics rule to an existing workspace.

Notes:
- Deploy into the **same resource group** that contains the Log Analytics workspace.
- You will be prompted for `workspaceName` (the Log Analytics workspace name) and can toggle `enableRule`.
- If you're using Azure US Government, replace `portal.azure.com` with `portal.azure.us` in the deploy URL.

| Rule | Deploy |
|---|---|
| Azure Policy assignment deleted or set to DoNotEnforce | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FPolicyAssignmentDeletedOrDisabled.json) |
| Azure resource lock deleted | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FResourceLockDeleted.json) |
| Default route (0.0.0.0/0) to Internet or virtual appliance added | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FDefaultRouteToInternetOrNVAAdded.json) |
| Diagnostic settings deleted or all logs disabled | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FDiagnosticSettingsDeletedOrDisabled.json) |
| Key Vault public network access or firewall allow enabled | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FKeyVaultPublicAccessEnabled.json) |
| NSG flow logs disabled or deleted | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FNSGFlowLogsDisabledOrDeleted.json) |
| NSG inbound allow from Internet to management ports | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FNSGInboundInternetToManagementPorts.json) |
| NSG outbound allow to Internet (risky egress) | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FNSGOutboundAllowToInternet.json) |
| Storage account public access enabled | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FStorageAccountPublicAccessEnabled.json) |
| Subnet created or updated without an NSG | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FSubnetWithoutNSGAssociation.json) |
| O365 inbox rule forwards or redirects to external address | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FO365InboxRuleForwardingToExternalDomain.json) |
| Successful legacy authentication sign-in | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FSuccessfulLegacyAuthenticationSignin.json) |
| Azure Automation runbook or webhook created or updated | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FAzureAutomationRunbookOrWebhookCreatedOrUpdated.json) |
| Local administrators group membership changed (Windows) | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FLocalAdminGroupMembershipChanged.json) |
| NSG inbound allow any-to-any rule created or updated | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fdeploy%2FNSGInboundAnyAnyRuleCreatedOrUpdated.json) |
