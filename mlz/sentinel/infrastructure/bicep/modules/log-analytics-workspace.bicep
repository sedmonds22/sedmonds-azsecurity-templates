targetScope = 'resourceGroup'

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Azure region for the Log Analytics workspace.')
param workspaceLocation string

@description('SKU for the workspace.')
@allowed([
  'PerGB2018'
  'PerNode'
  'Per500MB'
  'Standalone'
  'Standard'
])
param sku string

@description('Data retention in days.')
@minValue(30)
@maxValue(730)
param retentionInDays int

@description('Daily ingestion cap in GB. Use -1 to disable the cap.')
@minValue(-1)
param dailyQuotaGb int

@description('Tags to assign to the workspace.')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: workspaceLocation
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      immediatePurgeDataOn30Days: false
    }
    workspaceCapping: dailyQuotaGb >= 0 ? {
      dailyQuotaGb: dailyQuotaGb
    } : null
  }
}

output workspaceName string = workspace.name
output workspaceResourceId string = workspace.id
output workspaceCustomerId string = workspace.properties.customerId
