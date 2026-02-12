<#!
.SYNOPSIS
Configures Microsoft Sentinel data connectors for Azure Activity and Microsoft Entra ID.

.DESCRIPTION
Uses Azure Resource Manager REST calls through the Az PowerShell module to deploy
Microsoft Sentinel data connectors for the specified Log Analytics workspace. The script
supports enabling Azure Activity and Microsoft Entra ID connectors with configurable
log type states.

.EXAMPLE
PS> ./Enable-DataConnectors.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ResourceGroupName 'rg-sentinel-dev' -WorkspaceName 'law-sentinel-dev'

.PARAMETER SubscriptionId
Azure subscription identifier that hosts the Log Analytics workspace.

.PARAMETER ResourceGroupName
Name of the resource group containing the Log Analytics workspace.

.PARAMETER WorkspaceName
Name of the Log Analytics workspace with Microsoft Sentinel enabled.

.PARAMETER EnableAzureActivity
Switch that enables the Azure Activity connector when present.

.PARAMETER EnableEntraId
Switch that enables the Microsoft Entra ID connector when present.

.PARAMETER EntraDataTypeStates
Hashtable mapping Microsoft Entra ID log tables to connector state values (Enabled/Disabled).

.PARAMETER ApiVersion
API version used when invoking the Microsoft Sentinel data connector resource provider.

.NOTES
Requires the Az PowerShell modules. Caller must have Microsoft Sentinel Contributor permissions
on the target workspace and appropriate Microsoft Entra permissions for diagnostic settings.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter()]
    [switch]$EnableAzureActivity,

    [Parameter()]
    [switch]$EnableEntraId,

    [Parameter()]
    [hashtable]$EntraDataTypeStates = @{
        SignInLogs                  = 'Enabled'
        AuditLogs                   = 'Enabled'
        NonInteractiveUserSignInLogs = 'Enabled'
        ServicePrincipalSignInLogs  = 'Enabled'
        ManagedIdentitySignInLogs   = 'Enabled'
        ProvisioningLogs            = 'Enabled'
        ADFSSignInLogs              = 'Enabled'
        RiskyUsers                  = 'Enabled'
        RiskyServicePrincipals      = 'Enabled'
        RiskEvents                  = 'Enabled'
        RiskyUsersRiskEvents        = 'Enabled'
        UserRiskEvents              = 'Enabled'
    },

    [Parameter()]
    [string]$ApiVersion = '2022-11-01-preview'
)

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw 'Az PowerShell modules are required. Install-Module Az -Scope CurrentUser'
}

if (-not (Get-Module -ListAvailable -Name Az.OperationalInsights)) {
    throw 'Az.OperationalInsights module is required. Install-Module Az.OperationalInsights -Scope CurrentUser'
}

Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$context = Get-AzContext
if (-not $context) {
    throw 'Unable to resolve Az context. Ensure you are logged in with Connect-AzAccount.'
}

$tenantId = $context.Tenant.Id
$null = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop

function Invoke-ConnectorDeployment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnectorId,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body
    )

    $payload = ($Body | ConvertTo-Json -Depth 10)
    $path = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors/$ConnectorId?api-version=$ApiVersion"

    Write-Verbose ("Applying connector '{0}'" -f $ConnectorId)
    Invoke-AzRestMethod -Method PUT -Path $path -Payload $payload -ErrorAction Stop | Out-Null
}

if ($EnableAzureActivity.IsPresent) {
    $azureActivityBody = @{
        kind       = 'AzureActivity'
        properties = @{
            tenantId  = $tenantId
            dataTypes = @{
                AzureActivity = @{
                    state = 'Enabled'
                }
            }
        }
    }

    Invoke-ConnectorDeployment -ConnectorId 'AzureActivity' -Body $azureActivityBody
}

if ($EnableEntraId.IsPresent) {
    $dataTypes = @{}
    foreach ($key in $EntraDataTypeStates.Keys) {
        $dataTypes[$key] = @{ state = $EntraDataTypeStates[$key] }
    }

    $entraBody = @{
        kind       = 'AzureActiveDirectory'
        properties = @{
            tenantId  = $tenantId
            dataTypes = $dataTypes
        }
    }

    Invoke-ConnectorDeployment -ConnectorId 'AzureActiveDirectory' -Body $entraBody
}

# Return basic status snapshot for pipeline consumption.
$result = [pscustomobject]@{
    SubscriptionId      = $SubscriptionId
    ResourceGroupName   = $ResourceGroupName
    WorkspaceName       = $WorkspaceName
    AzureActivityStatus = if ($EnableAzureActivity.IsPresent) { 'Configured' } else { 'Skipped' }
    EntraIdStatus       = if ($EnableEntraId.IsPresent) { 'Configured' } else { 'Skipped' }
}

return $result
