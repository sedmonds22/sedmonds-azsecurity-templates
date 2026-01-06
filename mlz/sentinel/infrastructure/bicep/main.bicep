targetScope = 'subscription'

@description('Azure region where the Mission LZ Sentinel resources will be deployed.')
param location string = 'eastus2'

@description('Resource group that hosts the MLZ Sentinel workspace and related assets.')
param resourceGroupName string

@description('Name of the Log Analytics workspace that underpins the MLZ Sentinel deployment.')
param workspaceName string

@description('Tag dictionary applied to the MLZ Sentinel resource group and workspace.')
param tags object = {
  workload: 'mlz-sentinel'
}

@description('SKU for the Log Analytics workspace.')
@allowed([
  'PerGB2018'
  'PerNode'
  'Per500MB'
  'Standard'
  'Standalone'
])
param workspaceSku string = 'PerGB2018'

@description('Daily ingestion cap for the workspace in GB. Use -1 for unlimited.')
@minValue(-1)
param dailyQuotaGb int = -1

@description('Data retention period for the workspace in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Enable Microsoft Sentinel and supporting analytics features.')
param enableSentinel bool = true

@description('Configure Entity Behavior Analytics (UEBA entity sync).')
param enableEntityBehavior bool = true

@description('Sets whether the deployment attempts to create or update the Entity Behavior Analytics setting.')
param deployEntityBehaviorSetting bool = true

@description('Enable UEBA data sources.')
param enableUeba bool = true

@description('Sets whether the deployment attempts to create or update the UEBA setting.')
param deployUebaSetting bool = true

@description('Data sources that should feed UEBA insights.')
param uebaDataSources array = [
  'SigninLogs'
  'AuditLogs'
  'AzureActivity'
]

@description('Ensure Sentinel anomaly detection is enabled.')
param enableAnomalies bool = true

@description('Enable Azure Activity diagnostics at the subscription scope.')
param enableAzureActivityDiagnostics bool = true

@description('Name of the Azure Activity diagnostic setting.')
param azureActivityDiagnosticName string = 'diag-azureactivity-mlz'

@description('Log categories to enable for Azure Activity diagnostics.')
param azureActivityLogCategories array = [
  'Administrative'
  'Security'
  'ServiceHealth'
  'Alert'
  'Recommendation'
  'Policy'
  'Autoscale'
  'ResourceHealth'
]

@description('Retention policy configuration for Azure Activity diagnostics.')
param azureActivityRetentionPolicy object = {
  enabled: false
  days: 0
}

@description('Enable Microsoft Entra ID diagnostics.')
param enableEntraDiagnostics bool = true

@description('Name of the Microsoft Entra ID diagnostic setting.')
param entraDiagnosticName string = 'diag-entra-mlz'

@description('Log categories to enable for Microsoft Entra ID diagnostics.')
param entraLogCategories array = [
  'AuditLogs'
  'SignInLogs'
  'NonInteractiveUserSignInLogs'
  'ServicePrincipalSignInLogs'
  'ManagedIdentitySignInLogs'
  'ProvisioningLogs'
  'ADFSSignInLogs'
  'RiskyUsers'
  'RiskyServicePrincipals'
  'UserRiskEvents'
]

@description('Retention policy configuration for Microsoft Entra ID diagnostics.')
param entraRetentionPolicy object = {
  enabled: false
  days: 0
}

resource solutionRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module workspace '../../../../bicep/modules/log-analytics-workspace.bicep' = {
  name: 'mlzLogAnalytics'
  scope: solutionRg
  params: {
    workspaceName: workspaceName
    workspaceLocation: location
    sku: workspaceSku
    retentionInDays: retentionInDays
    dailyQuotaGb: dailyQuotaGb
    tags: tags
  }
}

module sentinel '../../../../bicep/modules/sentinel-enable.bicep' = if (enableSentinel) {
  name: 'mlzSentinelEnablement'
  scope: solutionRg
  params: {
    workspaceName: workspaceName
    enableEntityBehavior: enableEntityBehavior
    deployEntityBehaviorSetting: deployEntityBehaviorSetting
    enableUeba: enableUeba
    deployUebaSetting: deployUebaSetting
    uebaDataSources: uebaDataSources
    enableAnomalies: enableAnomalies
  }
  dependsOn: [
    workspace
  ]
}

module azureActivityDiagnostics '../../../../bicep/modules/subscription-diagnostic-settings.bicep' = if (enableAzureActivityDiagnostics) {
  name: 'mlzAzureActivityDiagnostics'
  params: {
    diagnosticSettingName: azureActivityDiagnosticName
    workspaceResourceId: workspace.outputs.workspaceResourceId
    logCategories: azureActivityLogCategories
    retentionPolicy: azureActivityRetentionPolicy
  }
}

module entraDiagnostics '../../../../bicep/tenant/entra-diagnostic-settings.bicep' = if (enableEntraDiagnostics) {
  name: 'mlzEntraDiagnostics'
  scope: tenant()
  params: {
    diagnosticSettingName: entraDiagnosticName
    workspaceResourceId: workspace.outputs.workspaceResourceId
    logCategories: entraLogCategories
    retentionPolicy: entraRetentionPolicy
  }
}

output resourceGroupName string = solutionRg.name
output workspaceName string = workspace.outputs.workspaceName
output workspaceResourceId string = workspace.outputs.workspaceResourceId
output workspaceCustomerId string = workspace.outputs.workspaceCustomerId
