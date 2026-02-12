<#!
.SYNOPSIS
Deploys the core Azure Activity + Entra Sentinel infrastructure using Bicep.

.DESCRIPTION
Invokes a subscription-scoped Bicep deployment that provisions the solution resource group,
Log Analytics workspace, and optionally enables Microsoft Sentinel. Wraps Az PowerShell
commands for repeatable execution.

By default, this script also triggers `Deploy-Content.ps1` after a successful infrastructure
deployment when Microsoft Sentinel is enabled so workbooks and rules are available immediately.

.EXAMPLE
PS> ./Deploy-Infrastructure.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000'

Deploys infrastructure and then deploys Sentinel content (workbooks/rules) by default.

.EXAMPLE
PS> ./Deploy-Infrastructure.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -SkipContentDeployment

Deploys infrastructure only.

.PARAMETER SubscriptionId
Azure subscription identifier where the solution should be deployed.

.PARAMETER TemplateFile
Path to the subscription-scoped Bicep template. Defaults to bicep/main.bicep.

.PARAMETER ParametersFile
Path to the .bicepparam file providing environment-specific values.

.PARAMETER Location
Azure region for the deployment metadata. Should align with the workspace location.

.PARAMETER DeploymentName
Optional name for the subscription deployment. Defaults to a timestamped value.

.PARAMETER SkipContentDeployment
Skip running `Deploy-Content.ps1` after the infrastructure deployment.

.NOTES
Requires the Az PowerShell modules and permissions to deploy at subscription scope.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter()]
    [string]$TemplateFile = "${PSScriptRoot}\..\bicep\main.bicep",

    [Parameter()]
    [string]$ParametersFile = "${PSScriptRoot}\..\bicep\parameters\development.bicepparam",

    [Parameter()]
    [string]$Location = 'eastus2',

    [Parameter()]
    [string]$DeploymentName = "sentinel-infra-$(Get-Date -Format 'yyyyMMddHHmmss')",

    [Parameter()]
    [switch]$SkipContentDeployment,

    [Parameter()]
    [switch]$WhatIf
)

# Ensure Az module is available before attempting deployment.
if (-not (Get-Module -ListAvailable -Name Az)) {
    throw 'Az PowerShell modules are required. Install-Module Az -Scope CurrentUser'
}

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
        Write-Warning "Bicep CLI not found. Install via 'az bicep install' or add it to PATH."
    }
}

# Switch to the requested subscription context.
Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$deploymentParams = @{
    Name                   = $DeploymentName
    Location               = $Location
    TemplateFile           = (Resolve-Path -Path $TemplateFile).Path
    TemplateParameterFile  = (Resolve-Path -Path $ParametersFile).Path
}

if ($WhatIf.IsPresent) {
    $deploymentParams['WhatIf'] = $true
}

Write-Verbose ("Starting subscription deployment '{0}' using template '{1}'" -f $deploymentParams.Name, $deploymentParams.TemplateFile)

$deployment = New-AzSubscriptionDeployment @deploymentParams -ErrorAction Stop

Write-Verbose 'Deployment complete.'

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

if (-not $WhatIf.IsPresent -and -not $SkipContentDeployment.IsPresent) {
    $enableSentinel = Get-BicepParamBool -FilePath $deploymentParams.TemplateParameterFile -ParamName 'enableSentinel'
    if ($null -eq $enableSentinel) {
        $enableSentinel = $true
    }

    if ($enableSentinel) {
        if ($deployment -and $deployment.Outputs -and $deployment.Outputs.workspaceName -and $deployment.Outputs.resourceGroupName) {
            $workspaceName = $deployment.Outputs.workspaceName.Value
            $resourceGroupName = $deployment.Outputs.resourceGroupName.Value

            if ($workspaceName -and $resourceGroupName) {
                Write-Host "Deploying Sentinel Content (workbooks, rules) ..." -ForegroundColor Cyan
                $contentScript = Join-Path $PSScriptRoot 'Deploy-Content.ps1'
                & $contentScript -SubscriptionId $SubscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName
            }
            else {
                Write-Warning 'Infrastructure deployment did not return workspaceName/resourceGroupName outputs. Skipping content deployment.'
            }
        }
        else {
            Write-Warning 'Infrastructure deployment did not return expected outputs. Skipping content deployment.'
        }
    }
    else {
        Write-Verbose 'enableSentinel is false; skipping content deployment.'
    }
}

return $deployment
