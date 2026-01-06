using '../mlz.bicep'

// Azure Government multi-subscription deployment
param identifier = 'mlzgv'
param environmentAbbreviation = 'prod'
param location = 'usgovvirginia'

// Subscriptions
// - Operations + Security
param operationsSubscriptionId = '6d2cdf2f-3fbe-4679-95ba-4e8b7d9aed24'
// - Hub + Shared Services
param hubSubscriptionId = '3a8f043c-c15c-4a67-9410-a585a85f2109'
param sharedServicesSubscriptionId = '3a8f043c-c15c-4a67-9410-a585a85f2109'
// Identity tier (only two subs provided; defaulting to operations subscription)
param identitySubscriptionId = '6d2cdf2f-3fbe-4679-95ba-4e8b7d9aed24'

// Sentinel deployment
param deploySentinel = true
param enableEntraDiagnostics = false
param enableEntityBehavior = true
param deployEntityBehaviorSetting = true
param useEntityBehaviorScript = false
param enableUeba = true
param enableAnomalies = true
param deployUebaSetting = true
param enableEntraIdDataConnector = true
param deploySentinelAutomationScript = false

// Optional (safety): adopt an existing Activity Log diagnostic setting name if you already have one.
// param activityLogDiagnosticSettingNames = {
//   '6d2cdf2f-3fbe-4679-95ba-4e8b7d9aed24': 'diag-azureactivity-mlz03'
// }

// Other toggles
param deployDefender = false
param deployBastion = false
param deployLinuxVirtualMachine = false
param deployWindowsVirtualMachine = false
param logAnalyticsWorkspaceRetentionInDays = 120

param tags = {
  environment: 'usgovvirginia-gov'
  workload: 'mlz-sentinel'
}
