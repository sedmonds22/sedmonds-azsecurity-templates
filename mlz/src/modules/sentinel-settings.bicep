targetScope = 'resourceGroup'

@description('Name of the Log Analytics workspace where Microsoft Sentinel is enabled.')
param workspaceName string

@description('Azure region used for ancillary operations such as deployment scripts.')
param location string

@description('Toggle to configure the Entity Behavior Analytics setting.')
param enableEntityBehavior bool = true

@description('Skip provisioning the Entity Behavior Analytics setting when it already exists to avoid concurrency conflicts.')
param deployEntityBehaviorSetting bool = true

@description('Use the deployment script (recommended when the setting already exists) to upsert Entity Behavior. Disable for brand new workspaces to provision the resource directly.')
param useEntityBehaviorScript bool = true

@description('Toggle to configure UEBA data sources and ensure they participate in the ML fusion models.')
param enableUeba bool = true

@description('Skip provisioning the UEBA setting when it already exists to avoid concurrency conflicts.')
param deployUebaSetting bool = true

@description('Data sources that enrich UEBA insights.')
param uebaDataSources array = [
  'SigninLogs'
  'AuditLogs'
  'AzureActivity'
]

@description('Toggle to ensure Microsoft Sentinel anomaly detection remains enabled.')
param enableAnomalies bool = true

@description('Optional override for the Azure Security Insights service principal object ID if discovery via Microsoft Graph is restricted.')
param sentinelAutomationPrincipalId string = ''

@description('Toggle to run the deployment script that discovers and assigns the Sentinel automation service principal. Disable when you plan to handle the automation role manually later.')
param deploySentinelAutomationScript bool = true

var sentinelAutomationContributorRoleDefinitionGuid = 'f4c81013-99ee-4d62-a7ee-b3f1f648599a'
var workspaceContributorRoleDefinitionGuid = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var shouldRunAutomationScript = deploySentinelAutomationScript
var shouldConfigureEntitySetting = enableEntityBehavior && deployEntityBehaviorSetting
var shouldDeployEntitySettingDirect = false
var shouldConfigureUebaSetting = enableUeba && deployUebaSetting
var shouldConfigureAnomaliesSetting = enableAnomalies
var entityBehaviorSettingResourceId = extensionResourceId(workspace.id, 'Microsoft.SecurityInsights/settings', 'EntityAnalytics')
var entityBehaviorSettingPayload = string({
  kind: 'EntityAnalytics'
  properties: {
    entityProviders: [
      'AzureActiveDirectory'
    ]
  }
})

var uebaSettingResourceId = extensionResourceId(workspace.id, 'Microsoft.SecurityInsights/settings', 'Ueba')
var uebaSettingPayload = string({
  kind: 'Ueba'
  properties: {
    dataSources: uebaDataSources
  }
})

var anomaliesSettingResourceId = extensionResourceId(workspace.id, 'Microsoft.SecurityInsights/settings', 'Anomalies')
var anomaliesSettingPayload = string({
  kind: 'Anomalies'
  properties: {}
})

resource automationScriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'sentinel-script-${uniqueString(resourceGroup().id)}'
  location: location
}

resource automationScriptIdentityRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = if (shouldRunAutomationScript || shouldConfigureEntitySetting) {
  name: guid(resourceGroup().id, automationScriptIdentity.name, 'automation-script-rbac')
  properties: {
    principalId: automationScriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f1a07417-d97a-45cb-824c-7a7467783830') // User Access Administrator
  }
}

resource automationScriptSentinelRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = if (shouldConfigureEntitySetting || shouldConfigureUebaSetting || shouldConfigureAnomaliesSetting) {
  name: guid(workspace.id, automationScriptIdentity.name, 'automation-script-sentinel-rbac')
  scope: workspace
  properties: {
    principalId: automationScriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', workspaceContributorRoleDefinitionGuid)
  }
}

resource automationPrincipalLookup 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (shouldRunAutomationScript) {
  name: 'lookup-asi-sp-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${automationScriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.61.0'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    timeout: 'PT15M'
    forceUpdateTag: empty(sentinelAutomationPrincipalId) ? 'auto' : sentinelAutomationPrincipalId
    environmentVariables: [
      {
        name: 'SENTINEL_SP_OBJECT_ID_OVERRIDE'
        value: sentinelAutomationPrincipalId
      }
      {
        name: 'SENTINEL_AUTOMATION_SCOPE'
        value: resourceGroup().id
      }
      {
        name: 'SENTINEL_AUTOMATION_ROLE_ID'
        value: sentinelAutomationContributorRoleDefinitionGuid
      }
    ]
    scriptContent: '''
      principalId="$SENTINEL_SP_OBJECT_ID_OVERRIDE"
      if [ -z "$principalId" ]; then
        principalId=$(az ad sp list --display-name "Azure Security Insights" --query "[0].id" -o tsv)
      fi

      if [ -z "$principalId" ]; then
        echo "Azure Security Insights service principal not found" >&2
        exit 1
      fi

      scope="$SENTINEL_AUTOMATION_SCOPE"
      roleDefinitionId="$SENTINEL_AUTOMATION_ROLE_ID"

      existingAssignment=$(az role assignment list --scope "$scope" --assignee-object-id "$principalId" --role "$roleDefinitionId" --query "[0].id" -o tsv)

      if [ -z "$existingAssignment" ]; then
        az role assignment create --assignee-object-id "$principalId" --assignee-principal-type ServicePrincipal --role "$roleDefinitionId" --scope "$scope" --only-show-errors
      fi

      echo "{\"sentinelSpObjectId\": \"$principalId\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
  }
}
resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

resource sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = {
  name: 'default'
  scope: workspace
  properties: {
    customerManagedKey: false
  }
}

resource entityBehaviorSettingScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (shouldConfigureEntitySetting) {
  name: 'configure-entity-behavior-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${automationScriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.61.0'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    timeout: 'PT10M'
    environmentVariables: [
      {
        name: 'ENTITY_SETTING_ID'
        value: entityBehaviorSettingResourceId
      }
      {
        name: 'ENTITY_SETTING_PAYLOAD'
        value: entityBehaviorSettingPayload
      }
    ]
    scriptContent: '''
      set -euo pipefail

      resourceId="$ENTITY_SETTING_ID"
      apiVersion="2024-01-01-preview"
      payload="$ENTITY_SETTING_PAYLOAD"

      etag=$(az rest --method get --url "$resourceId?api-version=$apiVersion" --query etag -o tsv --only-show-errors 2>/dev/null || echo "")

      if [ -n "$etag" ]; then
        az rest --method put --headers "Content-Type=application/json" "If-Match=$etag" --url "$resourceId?api-version=$apiVersion" --body "$payload" --only-show-errors
      else
        az rest --method put --headers "Content-Type=application/json" "If-None-Match=*" --url "$resourceId?api-version=$apiVersion" --body "$payload" --only-show-errors
      fi
    '''
  }
  dependsOn: [
    sentinel
    automationScriptIdentityRoleAssignment
    automationScriptSentinelRoleAssignment
  ]
}

resource uebaSettingScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (shouldConfigureUebaSetting) {
  name: 'configure-ueba-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${automationScriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.61.0'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    timeout: 'PT10M'
    environmentVariables: [
      {
        name: 'UEBA_SETTING_ID'
        value: uebaSettingResourceId
      }
      {
        name: 'UEBA_SETTING_PAYLOAD'
        value: uebaSettingPayload
      }
    ]
    scriptContent: '''
      set -euo pipefail

      resourceId="$UEBA_SETTING_ID"
      apiVersion="2024-01-01-preview"
      payload="$UEBA_SETTING_PAYLOAD"

      etag=$(az rest --method get --url "$resourceId?api-version=$apiVersion" --query etag -o tsv --only-show-errors 2>/dev/null || echo "")

      if [ -n "$etag" ]; then
        az rest --method put --headers "Content-Type=application/json" "If-Match=$etag" --url "$resourceId?api-version=$apiVersion" --body "$payload" --only-show-errors
      else
        az rest --method put --headers "Content-Type=application/json" "If-None-Match=*" --url "$resourceId?api-version=$apiVersion" --body "$payload" --only-show-errors
      fi
    '''
  }
  dependsOn: [
    sentinel
    automationScriptSentinelRoleAssignment
  ]
}

resource anomaliesSettingScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (shouldConfigureAnomaliesSetting) {
  name: 'configure-anomalies-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${automationScriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.61.0'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    timeout: 'PT10M'
    environmentVariables: [
      {
        name: 'ANOMALIES_SETTING_ID'
        value: anomaliesSettingResourceId
      }
      {
        name: 'ANOMALIES_SETTING_PAYLOAD'
        value: anomaliesSettingPayload
      }
    ]
    scriptContent: '''
      set -euo pipefail

      resourceId="$ANOMALIES_SETTING_ID"
      apiVersion="2024-01-01-preview"
      payload="$ANOMALIES_SETTING_PAYLOAD"

      etag=$(az rest --method get --url "$resourceId?api-version=$apiVersion" --query etag -o tsv --only-show-errors 2>/dev/null || echo "")

      if [ -n "$etag" ]; then
        az rest --method put --headers "Content-Type=application/json" "If-Match=$etag" --url "$resourceId?api-version=$apiVersion" --body "$payload" --only-show-errors
      else
        az rest --method put --headers "Content-Type=application/json" "If-None-Match=*" --url "$resourceId?api-version=$apiVersion" --body "$payload" --only-show-errors
      fi
    '''
  }
  dependsOn: [
    sentinel
    automationScriptSentinelRoleAssignment
  ]
}


output sentinelResourceId string = sentinel.id
