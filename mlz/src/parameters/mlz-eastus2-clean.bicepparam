using '../mlz.bicep'

param identifier = 'mlz04'
param environmentAbbreviation = 'dev'
param location = 'eastus2'
param hubSubscriptionId = 'a3c32389-f2a2-40c1-a08f-f21215a4f936'
param identitySubscriptionId = 'a3c32389-f2a2-40c1-a08f-f21215a4f936'
param operationsSubscriptionId = 'a3c32389-f2a2-40c1-a08f-f21215a4f936'
param sharedServicesSubscriptionId = 'a3c32389-f2a2-40c1-a08f-f21215a4f936'
param deployDefender = false
param deployBastion = false
param deployLinuxVirtualMachine = false
param deployWindowsVirtualMachine = false
param deploySentinel = true
param enableEntityBehavior = true
param deployEntityBehaviorSetting = true
param useEntityBehaviorScript = false
param enableUeba = true
param enableAnomalies = true
param deployUebaSetting = true
param enableEntraIdDataConnector = true
param deploySentinelAutomationScript = false
param logAnalyticsWorkspaceRetentionInDays = 120
param tags = {
  environment: 'eastus2-dev'
  workload: 'mlz-sentinel'
}
