<#
.SYNOPSIS
    Orchestrates the complete deployment of the MLZ Sentinel solution, including infrastructure, content, playbooks, and automation.
    Handles idempotency for UEBA settings to avoid ETag conflicts.

.DESCRIPTION
    This script performs the following steps:
    1. Analyzes the environment to determine if Sentinel UEBA settings already exist.
    2. Deploys the MLZ Infrastructure (Bicep) with appropriate parameters to avoid conflicts.
    3. Deploys Sentinel Playbooks (Logic Apps).
    4. Deploys Sentinel Content (Analytic Rules, Workbooks).
    5. Finalizes Sentinel Automation (Managed Identity roles).

.PARAMETER SubscriptionId
    The Subscription ID where the deployment will occur.

.PARAMETER Location
    The Azure region for the deployment. Defaults to 'eastus2'.

.PARAMETER TemplateFile
    Path to the MLZ Bicep template. Defaults to 'mlz/src/mlz.bicep'.

.PARAMETER ParameterFile
    Path to the Bicep parameter file. Defaults to 'mlz/src/parameters/mlz-eastus2-clean.bicepparam'.

.EXAMPLE
    .\Deploy-All.ps1 -SubscriptionId "a3c32389-f2a2-40c1-a08f-f21215a4f936"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateSet('AzureCloud', 'AzureUSGovernment')]
    [string]$Environment = 'AzureCloud',

    [Parameter()]
    [string]$TenantId,

    [string]$Location = 'eastus2',

    [string]$TemplateFile = 'mlz/src/mlz.bicep',

    [string]$ParameterFile = 'mlz/src/parameters/mlz-eastus2-clean.bicepparam'

    ,
    [Parameter()]
    [System.Security.SecureString]$WindowsVmAdminPassword,

    [Parameter()]
    [string]$WindowsVmAdminUsername
)

$ErrorActionPreference = 'Stop'

# Ensure the Bicep CLI is discoverable for nested template compilation.
if (-not (Get-Command -Name bicep -ErrorAction SilentlyContinue)) {
    $defaultBicepDir = Join-Path $env:USERPROFILE '.azure\bin'
    $defaultBicepExe = Join-Path $defaultBicepDir 'bicep.exe'

    if (Test-Path -Path $defaultBicepExe) {
        if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $defaultBicepDir })) {
            $env:PATH = "${defaultBicepDir};$env:PATH"
        }
    }
    else {
        Write-Warning "Bicep CLI not found. Install via 'az bicep install' or add it to PATH. Deployments using .bicep templates may fail."
    }
}

# Helper to get absolute path
function Get-AbsolutePath {
    param($Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return Join-Path $PWD $Path
}

$TemplateFile = Get-AbsolutePath $TemplateFile
$ParameterFile = Get-AbsolutePath $ParameterFile

function Get-BicepParamBool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$ParamName
    )

    $match = Select-String -Path $FilePath -Pattern ("^\s*param\s+{0}\s*=\s*(true|false)\s*$" -f [regex]::Escape($ParamName)) -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $match) {
        return $null
    }

    return [bool]::Parse($match.Matches.Groups[1].Value)
}

function ConvertFrom-SecureStringPlaintext {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Secure
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$enableEntraIdDataConnector = Get-BicepParamBool -FilePath $ParameterFile -ParamName 'enableEntraIdDataConnector'
$deployWindowsVirtualMachine = Get-BicepParamBool -FilePath $ParameterFile -ParamName 'deployWindowsVirtualMachine'

Write-Host "Starting MLZ Complete Deployment..." -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId"
Write-Host "Environment: $Environment"
Write-Host "Location: $Location"
Write-Host "Template: $TemplateFile"
Write-Host "Parameters: $ParameterFile"

# Ensure we are authenticated (Government vs Public cloud matters).
try {
    $ctx = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        $connectParams = @{ Environment = $Environment }
        if ($TenantId) { $connectParams['Tenant'] = $TenantId }
        Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
    }
}
catch {
    throw "Failed to establish Azure context. Ensure you can sign in to $Environment. $($_.Exception.Message)"
}

# Optional: per-subscription override map for adopting existing Activity Log diagnostic setting names.
$activityLogDiagnosticSettingNames = $null

# 1. Parse Parameter File for Identifier (to find existing workspace)
$identifier = Select-String -Path $ParameterFile -Pattern "param identifier = '(.*)'" | ForEach-Object { $_.Matches.Groups[1].Value }
if (-not $identifier) {
    Write-Warning "Could not parse 'identifier' from parameter file. Assuming fresh deployment or relying on manual checks."
} else {
    Write-Host "Detected Identifier: $identifier"
}

# 2. Check for existing UEBA Settings to determine deployment flags
$deployUebaSetting = $true
$deployEntityBehaviorSetting = $true
$enableAnomalies = $true

if ($identifier) {
    Write-Host "Checking for existing Sentinel Workspace with identifier '$identifier'..."
    
    # Find workspace by tag
    $workspace = Get-AzResource -TagName 'identifier' -TagValue $identifier -ResourceType 'Microsoft.OperationalInsights/workspaces' -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($workspace) {
        Write-Host "Found existing workspace: $($workspace.Name) in $($workspace.ResourceGroupName)"

        # Adopt existing Activity Log diagnostic setting name (if present) so the infra deployment updates
        # that setting instead of attempting to create a new one which can conflict.
        try {
            $diagListPath = "/subscriptions/$SubscriptionId/providers/microsoft.insights/diagnosticSettings?api-version=2017-05-01-preview"
            $diagList = Invoke-AzRestMethod -Method GET -Path $diagListPath -ErrorAction Stop
            $diagContent = $diagList.Content | ConvertFrom-Json -ErrorAction Stop

            $workspaceIdToMatch = $workspace.ResourceId
            $existingActivityDiag = @(
                $diagContent.value |
                    Where-Object { $_.properties -and $_.properties.workspaceId -and ($_.properties.workspaceId -eq $workspaceIdToMatch) } |
                    Select-Object -First 1
            )

            if ($existingActivityDiag -and $existingActivityDiag.name) {
                $activityLogDiagnosticSettingNames = @{ $SubscriptionId = [string]$existingActivityDiag.name }
                Write-Host "Adopting existing Activity Log diagnostic setting: $($existingActivityDiag.name)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Warning "Unable to inspect existing Activity Log diagnostic settings. Proceeding with default name. $($_.Exception.Message)"
        }
        
        # Check for EntityAnalytics
        $entityAnalyticsId = "$($workspace.ResourceId)/providers/Microsoft.SecurityInsights/settings/EntityAnalytics"
        $uebaId = "$($workspace.ResourceId)/providers/Microsoft.SecurityInsights/settings/Ueba"
        $anomaliesId = "$($workspace.ResourceId)/providers/Microsoft.SecurityInsights/settings/Anomalies"
        
        function Test-ArmResourceExists {
            param(
                [Parameter(Mandatory = $true)]
                [string]$ResourceId,

                [Parameter(Mandatory = $true)]
                [string]$ApiVersion
            )

            try {
                $null = Invoke-AzRestMethod -Method GET -Path ("{0}?api-version={1}" -f $ResourceId, $ApiVersion) -ErrorAction Stop
                return $true
            }
            catch {
                return $false
            }
        }

        try {
            if (Test-ArmResourceExists -ResourceId $entityAnalyticsId -ApiVersion '2024-01-01-preview') {
                Write-Host "EntityAnalytics setting already exists. Disabling deployment to avoid ETag conflict." -ForegroundColor Yellow
                $deployEntityBehaviorSetting = $false
            }
        } catch {
            Write-Verbose "EntityAnalytics not found."
        }

        try {
            if (Test-ArmResourceExists -ResourceId $uebaId -ApiVersion '2024-01-01-preview') {
                Write-Host "UEBA setting already exists. Disabling deployment to avoid ETag conflict." -ForegroundColor Yellow
                $deployUebaSetting = $false
            }
        } catch {
            Write-Verbose "UEBA not found."
        }

        try {
            if (Test-ArmResourceExists -ResourceId $anomaliesId -ApiVersion '2024-01-01-preview') {
                Write-Host "Anomalies setting already exists. Disabling deployment to avoid ETag conflict." -ForegroundColor Yellow
                $enableAnomalies = $false
            }
        } catch {
            Write-Verbose "Anomalies not found."
        }

        # If the Entra connector already exists, do not attempt to update it.
        # In primary workspaces managed via Defender/MTP, connector updates are blocked and will fail the deployment.
        $entraConnectorId = "$($workspace.ResourceId)/providers/Microsoft.SecurityInsights/dataConnectors/AzureActiveDirectory"
        try {
            if (Test-ArmResourceExists -ResourceId $entraConnectorId -ApiVersion '2022-11-01-preview') {
                if ($null -eq $enableEntraIdDataConnector -or $enableEntraIdDataConnector -eq $true) {
                    Write-Host "Microsoft Entra ID data connector already exists. Skipping connector deployment to avoid blocked updates on primary workspaces." -ForegroundColor Yellow
                    $enableEntraIdDataConnector = $false
                }
            }
        } catch {
            Write-Verbose "Entra connector existence check failed."
        }
    } else {
        Write-Host "No existing workspace found. Proceeding with fresh deployment settings."
    }
}

# 3. Deploy Infrastructure
$deploymentName = "mlz-complete-$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "Deploying Infrastructure (Name: $deploymentName)..." -ForegroundColor Cyan

# Note: We explicitly set useEntityBehaviorScript to false to avoid permission issues.
$deploymentParams = @{
    Name                  = $deploymentName
    Location              = $Location
    TemplateFile          = $TemplateFile
    TemplateParameterFile = $ParameterFile
    deployUebaSetting     = $deployUebaSetting
    deployEntityBehaviorSetting = $deployEntityBehaviorSetting
    enableAnomalies       = $enableAnomalies
    useEntityBehaviorScript = $false
}

if ($deployWindowsVirtualMachine -eq $true) {
    if (-not $WindowsVmAdminPassword) {
        $WindowsVmAdminPassword = Read-Host -AsSecureString "Enter Windows VM admin password (min 12 chars)"
    }

    $deploymentParams['windowsVmAdminPassword'] = ConvertFrom-SecureStringPlaintext -Secure $WindowsVmAdminPassword

    if ($WindowsVmAdminUsername) {
        $deploymentParams['windowsVmAdminUsername'] = $WindowsVmAdminUsername
    }
}

if ($null -ne $enableEntraIdDataConnector) {
    $deploymentParams['enableEntraIdDataConnector'] = $enableEntraIdDataConnector
}

if ($activityLogDiagnosticSettingNames) {
    $deploymentParams['activityLogDiagnosticSettingNames'] = $activityLogDiagnosticSettingNames
}

function Test-DeploymentHasPrimaryWorkspaceFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploymentName
    )

    try {
        $ops = Get-AzSubscriptionDeploymentOperation -DeploymentName $DeploymentName -ErrorAction Stop
        foreach ($op in $ops) {
            if ($op.StatusMessage -and ($op.StatusMessage -match 'aka\.ms/primaryWorkspace')) {
                return $true
            }
        }
    }
    catch {
        # If we cannot query operations, treat as unknown (no retry trigger).
    }

    return $false
}

$deployment = $null
try {
    $deployment = New-AzSubscriptionDeployment @deploymentParams
}
catch {
    $message = $_.Exception.Message
    if ($message -match 'aka\.ms/primaryWorkspace') {
        $deployment = [pscustomobject]@{ ProvisioningState = 'Failed' }
    }
    else {
        throw
    }
}

if ($deployment.ProvisioningState -ne 'Succeeded') {
    if ((Test-DeploymentHasPrimaryWorkspaceFailure -DeploymentName $deploymentName) -and (-not ($deploymentParams.ContainsKey('enableEntraIdDataConnector') -and $deploymentParams['enableEntraIdDataConnector'] -eq $false))) {
        Write-Warning "Microsoft Entra data connector deployment is blocked because this workspace is managed as a primary workspace via Microsoft Threat Protection/Defender portal. Retrying infrastructure deployment with enableEntraIdDataConnector=false so the rest of the solution can deploy."
        $deploymentParams['enableEntraIdDataConnector'] = $false
        $deployment = New-AzSubscriptionDeployment @deploymentParams
    }
}

if ($deployment.ProvisioningState -ne 'Succeeded') {
    Write-Error "Infrastructure deployment failed. Status: $($deployment.ProvisioningState)"
}

# 4. Extract Outputs
$outputs = $deployment.Outputs
if (-not $outputs) {
    Write-Error "No outputs returned from deployment. Cannot proceed with content deployment."
}

$lawResourceId = $outputs['logAnalyticsWorkspaceResourceId'].Value
if (-not $lawResourceId) {
    Write-Error "Output 'logAnalyticsWorkspaceResourceId' not found."
}

# Parse Resource ID
# /subscriptions/{sub}/resourceGroups/{rg}/providers/.../workspaces/{name}
$parts = $lawResourceId -split '/'
$resourceGroupName = $parts[4]
$workspaceName = $parts[8]

Write-Host "Infrastructure Deployed Successfully." -ForegroundColor Green
Write-Host "Resource Group: $resourceGroupName"
Write-Host "Workspace: $workspaceName"

# 5. Deploy Playbooks
Write-Host "Deploying Playbooks..." -ForegroundColor Cyan
$playbookScript = Join-Path $PSScriptRoot "Deploy-Playbooks.ps1"
# Exclude 'Prompt-User' as it requires Teams IDs which are not available in a zero-touch deployment
$playbooksToDeploy = @('Block-AADUser','Reset-AADUserPassword','Revoke-AADSignInSessions')
& $playbookScript -SubscriptionId $SubscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -AssignSentinelResponder -Playbooks $playbooksToDeploy

# 6. Deploy Content (Rules, Workbooks)
Write-Host "Deploying Content..." -ForegroundColor Cyan
$contentScript = Join-Path $PSScriptRoot "Deploy-Content.ps1"
& $contentScript -SubscriptionId $SubscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName

# 7. Finalize Automation
Write-Host "Finalizing Automation..." -ForegroundColor Cyan
$automationScript = Join-Path $PSScriptRoot "Finalize-SentinelAutomation.ps1"
& $automationScript -SubscriptionId $SubscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName

Write-Host "MLZ Complete Deployment Finished Successfully!" -ForegroundColor Green
