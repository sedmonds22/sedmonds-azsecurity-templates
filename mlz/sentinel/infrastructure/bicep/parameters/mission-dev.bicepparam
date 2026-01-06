using '../main.bicep'

param resourceGroupName = 'rg-mlz-sentinel-dev'
param workspaceName = 'law-mlz-sentinel-dev'
param location = 'eastus2'
param retentionInDays = 120
param enableEntityBehavior = true
param deployEntityBehaviorSetting = false
param enableUeba = true
param deployUebaSetting = false
param enableAnomalies = true
param enableAzureActivityDiagnostics = true
param enableEntraDiagnostics = true
param tags = {
  environment: 'development'
  workload: 'mlz-sentinel'
  mission: 'landing-zone'
}
param azureActivityDiagnosticName = 'diag-azureactivity-mlz-dev'
param entraDiagnosticName = 'diag-entra-mlz-dev'
