using "../mlz.bicep"

param identifier = 'mlzc'
param environmentAbbreviation = 'dev'
param location = 'centralus'
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
param enableUeba = true
param enableAnomalies = true
param enableAzureActivityDataConnector = true
param logAnalyticsWorkspaceRetentionInDays = 120
param tags = {
  environment: 'centralus-dev'
  workload: 'mlz-sentinel'
}
