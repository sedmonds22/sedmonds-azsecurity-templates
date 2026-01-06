<#!
.SYNOPSIS
Deploys the Mission Landing Zone (MLZ) Sentinel infrastructure using the MLZ-specific Bicep template.

.DESCRIPTION
Wraps the subscription-scoped MLZ Sentinel Bicep deployment with sensible defaults aligned to the
Mission Landing Zone architecture. Ensures the subscription context is set prior to invoking
`New-AzSubscriptionDeployment` so the Log Analytics workspace, diagnostic settings, and Microsoft
Sentinel configuration are provisioned consistently.

.EXAMPLE
PS> ./Deploy-MLZInfrastructure.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000'

.PARAMETER SubscriptionId
Azure subscription identifier targeted for the MLZ Sentinel deployment.

.PARAMETER TemplateFile
Path to the MLZ Sentinel subscription-scoped Bicep template.

.PARAMETER ParametersFile
Path to the MLZ-focused .bicepparam file supplying environment values.

.PARAMETER Location
Azure region used for the deployment operation metadata. Should match the workspace location.

.PARAMETER DeploymentName
Optional name for the subscription deployment. Defaults to a timestamped value.

.NOTES
Requires the Az PowerShell modules and permissions to deploy at subscription scope.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter()]
    [string]$TemplateFile = "${PSScriptRoot}\..\..\infrastructure\bicep\main.bicep",

    [Parameter()]
    [string]$ParametersFile = "${PSScriptRoot}\..\..\infrastructure\bicep\parameters\mission-dev.bicepparam",

    [Parameter()]
    [string]$Location = 'eastus2',

    [Parameter()]
    [string]$DeploymentName = "mlz-sentinel-infra-$(Get-Date -Format 'yyyyMMddHHmmss')"
)

if (-not (Get-Module -ListAvailable -Name Az)) {
    throw 'Az PowerShell modules are required. Install-Module Az -Scope CurrentUser'
}

Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$deploymentParams = @{
    Name                  = $DeploymentName
    Location              = $Location
    TemplateFile          = (Resolve-Path -Path $TemplateFile).Path
    TemplateParameterFile = (Resolve-Path -Path $ParametersFile).Path
}

Write-Verbose (
    "Starting MLZ Sentinel subscription deployment '{0}' using template '{1}'" -f 
        $deploymentParams.Name, 
        $deploymentParams.TemplateFile
)

$deployment = New-AzSubscriptionDeployment @deploymentParams -ErrorAction Stop

Write-Verbose 'MLZ Sentinel infrastructure deployment complete.'
return $deployment
