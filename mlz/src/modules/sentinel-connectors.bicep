targetScope = 'resourceGroup'

@description('Name of the Log Analytics workspace that hosts Microsoft Sentinel.')
param workspaceName string

@description('Tenant ID associated with the Microsoft Sentinel workspace.')
param tenantId string

@description('Toggle to configure the Microsoft Entra ID data connector within Microsoft Sentinel.')
param enableEntraConnector bool = true

@description('Desired state (Enabled/Disabled) for each Microsoft Entra ID log type exposed by the data connector.')
param entraDataTypeStates object = {
  SignInLogs: 'Enabled'
  AuditLogs: 'Enabled'
  NonInteractiveUserSignInLogs: 'Enabled'
  ServicePrincipalSignInLogs: 'Enabled'
  ManagedIdentitySignInLogs: 'Enabled'
  ProvisioningLogs: 'Enabled'
  ADFSSignInLogs: 'Enabled'
  UserRiskEvents: 'Enabled'
  RiskyUsers: 'Enabled'
  RiskyServicePrincipals: 'Enabled'
  alerts: 'Enabled'
}

var normalizedEntraDataTypes = {
  SignInLogs: {
    state: entraDataTypeStates.SignInLogs
  }
  AuditLogs: {
    state: entraDataTypeStates.AuditLogs
  }
  NonInteractiveUserSignInLogs: {
    state: entraDataTypeStates.NonInteractiveUserSignInLogs
  }
  ServicePrincipalSignInLogs: {
    state: entraDataTypeStates.ServicePrincipalSignInLogs
  }
  ManagedIdentitySignInLogs: {
    state: entraDataTypeStates.ManagedIdentitySignInLogs
  }
  ProvisioningLogs: {
    state: entraDataTypeStates.ProvisioningLogs
  }
  ADFSSignInLogs: {
    state: entraDataTypeStates.ADFSSignInLogs
  }
  UserRiskEvents: {
    state: entraDataTypeStates.UserRiskEvents
  }
  RiskyUsers: {
    state: entraDataTypeStates.RiskyUsers
  }
  RiskyServicePrincipals: {
    state: entraDataTypeStates.RiskyServicePrincipals
  }
  alerts: {
    state: entraDataTypeStates.alerts
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

resource entraConnector 'Microsoft.SecurityInsights/dataConnectors@2022-11-01-preview' = if (enableEntraConnector) {
  name: 'AzureActiveDirectory'
  scope: workspace
  kind: 'AzureActiveDirectory'
  properties: {
    tenantId: tenantId
    dataTypes: json(string(normalizedEntraDataTypes))
  }
}
