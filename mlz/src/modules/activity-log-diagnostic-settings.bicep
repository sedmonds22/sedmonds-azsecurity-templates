/*
Copyright (c) Microsoft Corporation.
Licensed under the MIT License.
*/

targetScope = 'subscription'

param logAnalyticsWorkspaceId string

@description('Optional override for the Activity Log diagnostic setting name. When empty, a deterministic default name based on the subscription ID is used.')
param diagnosticSettingName string = ''

var effectiveDiagnosticSettingName = empty(diagnosticSettingName)
  ? 'diag-activity-log-${subscription().subscriptionId}'
  : diagnosticSettingName

// Export Activity Log to LAW
resource diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2017-05-01-preview' =  {
  name: effectiveDiagnosticSettingName
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Administrative'
        enabled: true
      }
      {
        category: 'Security'
        enabled: true
      }
      {
        category: 'ServiceHealth'
        enabled: true
      }
      {
        category: 'Alert'
        enabled: true
      }
      {
        category: 'Recommendation'
        enabled: true
      }
      {
        category: 'Policy'
        enabled: true
      }
      {
        category: 'Autoscale'
        enabled: true
      }
      {
        category: 'ResourceHealth'
        enabled: true
      }
    ]
  }
}
