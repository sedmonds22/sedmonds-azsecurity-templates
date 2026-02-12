<#
.SYNOPSIS
Runs the MLZ + Sentinel deployment across multiple subscriptions (supports Azure Government).

.DESCRIPTION
Thin wrapper around scripts/Deploy-All.ps1 that:
- Connects once (optional) to AzureCloud or AzureUSGovernment
- Iterates subscription IDs
- Writes per-subscription status files under .tmp/

.EXAMPLE
PS> ./scripts/Deploy-MultiSubscription.ps1 -Environment AzureUSGovernment -TenantId <tenant-guid> -SubscriptionIds @('<sub1>','<sub2>')

.NOTES
This script does not change the underlying deployment behavior; it just loops and records results.
#>
param(
    [Parameter(Mandatory = $true)]
    [string[]]$SubscriptionIds,

    [Parameter()]
    [ValidateSet('AzureCloud', 'AzureUSGovernment')]
    [string]$Environment = 'AzureCloud',

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$Location = 'eastus2',

    [Parameter()]
    [string]$TemplateFile = 'mlz/src/mlz.bicep',

    [Parameter()]
    [string]$ParameterFile = 'mlz/src/parameters/mlz-eastus2-clean.bicepparam'
)

$ErrorActionPreference = 'Stop'

# Connect once.
$ctx = Get-AzContext -ErrorAction SilentlyContinue
if (-not $ctx) {
    $connectParams = @{ Environment = $Environment }
    if ($TenantId) { $connectParams['Tenant'] = $TenantId }
    Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
}

$tmpDir = Join-Path $PSScriptRoot '..\.tmp'
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

$deployAll = Join-Path $PSScriptRoot 'Deploy-All.ps1'

$results = @()
foreach ($sub in $SubscriptionIds) {
    $name = "mlz-multi-$($sub)-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $statusPath = Join-Path $tmpDir "$name.status.txt"

    Write-Host "==== Deploying subscription $sub ($Environment) ====" -ForegroundColor Cyan

    try {
        & $deployAll -SubscriptionId $sub -Environment $Environment -TenantId $TenantId -Location $Location -TemplateFile $TemplateFile -ParameterFile $ParameterFile 2>&1 | Tee-Object -FilePath $statusPath
        $results += [pscustomobject]@{ SubscriptionId = $sub; Status = 'Completed'; Log = $statusPath }
    }
    catch {
        "FAILED: $($_.Exception.Message)" | Out-File -FilePath $statusPath -Append
        $results += [pscustomobject]@{ SubscriptionId = $sub; Status = 'Failed'; Log = $statusPath }
    }
}

$results | Format-Table -AutoSize
return $results
