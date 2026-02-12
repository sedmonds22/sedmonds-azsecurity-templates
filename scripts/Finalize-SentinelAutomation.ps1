<#!
.SYNOPSIS
Grants the Microsoft Sentinel Automation Contributor role to the Azure Security Insights service principal after all Sentinel assets are deployed.

.DESCRIPTION
Deploys the sentinel-automation-access Bicep template to create (or reuse) a user-assigned managed identity,
assign the User Access Administrator role to that identity, and run the deployment script that discovers the
Azure Security Insights service principal. Run this script near the end of the deployment workflow, after
content, connectors, workbooks, and playbooks have been provisioned.

.PARAMETER SubscriptionId
Azure subscription identifier that hosts the Sentinel workspace resource group.

.PARAMETER ResourceGroupName
Resource group where the Sentinel workspace resides and where the automation identity should live.

.PARAMETER WorkspaceName
Name of the Sentinel workspace. Used for validation before running the automation template.

.PARAMETER TemplateFile
Path to the Bicep template that configures the automation identity and permissions.

.PARAMETER DeploymentName
Name assigned to the resource group deployment operation.

.PARAMETER SentinelAutomationPrincipalId
Optional override for the Azure Security Insights service principal object ID if directory queries are blocked.

.PARAMETER AutomationIdentityName
Optional override for the user-assigned managed identity name.

.PARAMETER AutomationIdentityRoleDefinitionId
Optional override for the role definition resource ID granted to the automation identity (defaults to User Access Administrator).

.PARAMETER SentinelAutomationRoleDefinitionId
Optional override for the role definition resource ID assigned to the Azure Security Insights principal (defaults to Microsoft Sentinel Automation Contributor).

.NOTES
Requires Az PowerShell modules (Accounts, Resources, OperationalInsights, ManagedServiceIdentity).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter()]
    [string]$TemplateFile = (Join-Path -Path $PSScriptRoot -ChildPath '..\bicep\modules\sentinel-automation-access.bicep'),

    [Parameter()]
    [string]$DeploymentName = "sentinel-automation-$(Get-Date -Format 'yyyyMMddHHmmss')",

    [Parameter()]
    [string]$SentinelAutomationPrincipalId,

    [Parameter()]
    [string]$AutomationIdentityName,

    [Parameter()]
    [string]$AutomationIdentityRoleDefinitionId,

    [Parameter()]
    [string]$SentinelAutomationRoleDefinitionId
)

$requiredModules = @('Az.Accounts','Az.Resources','Az.OperationalInsights','Az.ManagedServiceIdentity')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Required module '$module' is not installed. Install-Module $module -Scope CurrentUser"
    }
}

Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop

$resolvedTemplate = (Resolve-Path -Path $TemplateFile).Path
$parameterObject = @{}

if ($PSBoundParameters.ContainsKey('SentinelAutomationPrincipalId')) {
    $parameterObject['sentinelAutomationPrincipalId'] = $SentinelAutomationPrincipalId
}

if ($PSBoundParameters.ContainsKey('AutomationIdentityName')) {
    $parameterObject['automationIdentityName'] = $AutomationIdentityName
}

if ($PSBoundParameters.ContainsKey('AutomationIdentityRoleDefinitionId')) {
    $parameterObject['automationIdentityRoleDefinitionId'] = $AutomationIdentityRoleDefinitionId
}

if ($PSBoundParameters.ContainsKey('SentinelAutomationRoleDefinitionId')) {
    $parameterObject['sentinelAutomationRoleDefinitionId'] = $SentinelAutomationRoleDefinitionId
}

# Auto-resolve the Sentinel Service Principal ID if not provided
if (-not $parameterObject.ContainsKey('sentinelAutomationPrincipalId')) {
    Write-Verbose "Resolving 'Azure Security Insights' Service Principal ID..."
    try {
        $sp = Get-AzADServicePrincipal -DisplayName "Azure Security Insights" -ErrorAction Stop
        if ($sp) {
            $parameterObject['sentinelAutomationPrincipalId'] = $sp.Id
            Write-Verbose "Found Service Principal ID: $($sp.Id)"
        } else {
            Write-Warning "Could not find 'Azure Security Insights' Service Principal. The deployment script may fail if it lacks directory permissions."
        }
    } catch {
        Write-Warning "Failed to resolve Service Principal: $_. The deployment script will attempt to resolve it, but may fail."
    }
}

Write-Verbose (
    "Deploying Sentinel automation access in resource group '{0}' using template '{1}'" -f
        $ResourceGroupName,
        $resolvedTemplate
)

$deploymentResult = New-AzResourceGroupDeployment -Name $DeploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $resolvedTemplate -TemplateParameterObject $parameterObject -ErrorAction Stop

[pscustomobject]@{
    ResourceGroupName = $ResourceGroupName
    WorkspaceName     = $WorkspaceName
    DeploymentName    = $DeploymentName
    AutomationIdentityId = $deploymentResult.Outputs['automationIdentityResourceId'].Value
    SentinelAutomationPrincipalId = $deploymentResult.Outputs['sentinelAutomationPrincipalObjectId'].Value
}
