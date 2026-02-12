<#!
.SYNOPSIS
Validates the Azure Activity + Microsoft Entra ID Sentinel deployment.

.DESCRIPTION
Performs a series of read-only validation checks against the deployed environment and
returns a structured summary. The script confirms that the workspace exists, Sentinel
is enabled, diagnostic settings are in place, data connectors are configured, and playbooks
are deployed (optionally verifying Microsoft Sentinel Responder role assignments).

.EXAMPLE
PS> ./Test-Deployment.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' \
        -ResourceGroupName 'rg-sentinel-dev' -WorkspaceName 'law-sentinel-dev'

.PARAMETER SubscriptionId
Azure subscription to review.

.PARAMETER ResourceGroupName
Resource group containing the Log Analytics workspace.

.PARAMETER WorkspaceName
Log Analytics workspace name hosting Microsoft Sentinel.

.PARAMETER AzureActivityDiagnosticName
Name of the subscription-level diagnostic setting streaming Azure Activity logs.

.PARAMETER EntraDiagnosticName
Name of the Microsoft Entra ID diagnostic setting.

.PARAMETER PlaybookNames
Optional list of Logic App names to verify (defaults to Entra solution playbooks).

.PARAMETER ApiVersion
API version for Microsoft Sentinel data connector queries.

.PARAMETER VerifyResponderRole
Switch that checks whether each Logic App managed identity has the Microsoft Sentinel
Responder role assigned at the workspace scope.

.NOTES
Requires Az modules: Accounts, Resources, OperationalInsights, Monitor, LogicApp.
The caller needs Reader rights on the subscription/resource group and Microsoft Sentinel workspace.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter()]
    [string]$AzureActivityDiagnosticName = 'diag-azureactivity-dev',

    [Parameter()]
    [string]$EntraDiagnosticName = 'diag-entra-dev',

    [Parameter()]
    [string[]]$PlaybookNames = @(
        'Block-EntraIDUser-Incident',
        'Prompt-EntraIDUser-Incident',
        'Reset-EntraIDUserPassword-Incident',
        'Revoke-EntraIDSignInSessions-Incident'
    ),

    [Parameter()]
    [string]$ApiVersion = '2022-11-01-preview',

    [Parameter()]
    [switch]$VerifyResponderRole
)

$requiredModules = 'Az.Accounts', 'Az.Resources', 'Az.OperationalInsights', 'Az.Monitor', 'Az.LogicApp'
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Required module '$module' is not installed. Install-Module $module -Scope CurrentUser"
    }
}

Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop
$workspaceResourceId = $workspace.Id
$workspaceLocation = $workspace.Location

# Sentinel enablement check
$sentinelResourceId = "$workspaceResourceId/providers/Microsoft.SecurityInsights"
$sentinelEnabled = $false
try {
    $sentinelResource = Get-AzResource -ResourceId $sentinelResourceId -ErrorAction Stop
    $sentinelEnabled = $sentinelResource.Properties.provisioningState -eq 'Succeeded'
} catch {
    $sentinelEnabled = $false
}

# Diagnostic settings checks
$subscriptionDiagnostics = Get-AzDiagnosticSetting -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $AzureActivityDiagnosticName }
$entraDiagnostics = $null
try {
    $entraResponse = Invoke-AzRestMethod -Method GET -Path "/providers/Microsoft.aadiam/diagnosticSettings?api-version=2020-07-01-preview"
    if ($entraResponse.StatusCode -eq 200) {
        $entraJson = $entraResponse.Content | ConvertFrom-Json -Depth 10
        $entraDiagnostics = $entraJson.value | Where-Object { $_.name -eq $EntraDiagnosticName }
    }
} catch {
    Write-Verbose "Failed to query Microsoft Entra diagnostic settings: $_"
}

# Data connector checks
$connectorPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors?api-version=$ApiVersion"
$connectorResponse = Invoke-AzRestMethod -Method GET -Path $connectorPath -ErrorAction Stop
$connectorPayload = $connectorResponse.Content | ConvertFrom-Json -Depth 10
$connectorLookup = @{}
foreach ($connector in $connectorPayload.value) {
    $connectorLookup[$connector.name] = $connector
}

$azureActivityConnector = $connectorLookup['AzureActivity']
$entraConnector = $connectorLookup['AzureActiveDirectory']

# Playbook checks
$playbookStatus = @()
foreach ($name in $PlaybookNames) {
    $playbookInfo = [pscustomobject]@{
        Name                = $name
        Exists              = $false
        Location            = $null
        ResponderRole       = $null
        ManagedIdentityId   = $null
    }
    try {
        $logicApp = Get-AzLogicApp -ResourceGroupName $ResourceGroupName -Name $name -ErrorAction Stop
        $playbookInfo.Exists = $true
        $playbookInfo.Location = $logicApp.Location
        $principalId = $logicApp.Identity.PrincipalId
        $playbookInfo.ManagedIdentityId = $principalId
        if ($VerifyResponderRole.IsPresent -and $principalId) {
            $assignment = Get-AzRoleAssignment -ObjectId $principalId -Scope $workspaceResourceId -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq 'Microsoft Sentinel Responder' }
            $playbookInfo.ResponderRole = if ($assignment) { 'Assigned' } else { 'Missing' }
        }
    } catch {
        # Leave defaults
    }
    $playbookStatus += $playbookInfo
}

# Results summary
$result = [pscustomobject]@{
    SubscriptionId             = $SubscriptionId
    ResourceGroupName          = $ResourceGroupName
    WorkspaceName              = $WorkspaceName
    WorkspaceLocation          = $workspaceLocation
    SentinelEnabled            = $sentinelEnabled
    AzureActivityDiagnostic    = if ($subscriptionDiagnostics) { 'Present' } else { 'Missing' }
    EntraDiagnostic            = if ($entraDiagnostics) { 'Present' } else { 'Unknown' }
    AzureActivityConnector     = if ($azureActivityConnector) { $azureActivityConnector.properties.dataTypes.AzureActivity.state } else { 'NotFound' }
    EntraConnector             = if ($entraConnector) { $entraConnector.properties.dataTypes.SignInLogs.state } else { 'NotFound' }
    Playbooks                  = $playbookStatus
}

return $result
