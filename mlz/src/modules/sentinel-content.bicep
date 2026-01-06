targetScope = 'subscription'

@description('Suffix appended to the deployment name so module executions remain unique per run.')
param deploymentNameSuffix string

@description('Name of the Log Analytics workspace where Microsoft Sentinel is enabled.')
param workspaceName string

@description('Azure region that hosts the Log Analytics workspace.')
param workspaceLocation string

@description('Resource group that contains the Microsoft Sentinel workspace.')
param workspaceResourceGroupName string

@description('Subscription identifier that contains the Microsoft Sentinel workspace.')
param workspaceSubscriptionId string

@description('Display name assigned to the Azure Activity workbook that ships with the solution package.')
param azureActivityWorkbookName string = 'Azure Activity'

@description('Display name assigned to the Azure Service Health workbook included in the Azure Activity solution package.')
param azureServiceHealthWorkbookName string = 'Azure Service Health Workbook'

@description('Display name assigned to the Microsoft Entra ID audit workbook that ships with the solution package.')
param entraAuditWorkbookName string = 'Microsoft Entra ID Audit logs'

@description('Display name assigned to the Microsoft Entra ID sign-in workbook that ships with the solution package.')
param entraSigninWorkbookName string = 'Microsoft Entra ID Sign-in logs'

@description('Toggle to install the Azure Activity Microsoft Sentinel solution when Microsoft Sentinel is enabled.')
param deployAzureActivitySolution bool = true

@description('Toggle to install the Microsoft Entra ID Microsoft Sentinel solution when Microsoft Sentinel is enabled.')
param deployMicrosoftEntraSolution bool = true

module azureActivitySolution '../../../content/packages/azure-activity/mainTemplate.json' = if (deployAzureActivitySolution) {
  name: 'deploy-azure-activity-${deploymentNameSuffix}'
  scope: resourceGroup(workspaceSubscriptionId, workspaceResourceGroupName)
  params: {
    location: workspaceLocation
    'workspace-location': workspaceLocation
    workspace: workspaceName
    'workbook1-name': azureActivityWorkbookName
    'workbook2-name': azureServiceHealthWorkbookName
  }
}

module microsoftEntraSolution '../../../content/packages/microsoft-entra-id/mainTemplate.json' = if (deployMicrosoftEntraSolution) {
  name: 'deploy-entra-solution-${deploymentNameSuffix}'
  scope: resourceGroup(workspaceSubscriptionId, workspaceResourceGroupName)
  params: {
    location: workspaceLocation
    'workspace-location': workspaceLocation
    workspace: workspaceName
    'workbook1-name': entraAuditWorkbookName
    'workbook2-name': entraSigninWorkbookName
  }
}
