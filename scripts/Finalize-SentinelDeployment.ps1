<#
.SYNOPSIS
    Finalize Microsoft Sentinel deployment by deploying all components that require data to exist.

.DESCRIPTION
    This script should be run 15-30 minutes after the initial MLZ Sentinel deployment. It:
    1. Verifies Sentinel is enabled and data connectors are configured
    2. Checks if data is flowing to required tables
    3. Deploys analytic rules from the Content Hub manifest
    4. Reports on deployment status

.PARAMETER ResourceGroupName
    The resource group containing the Sentinel workspace (e.g., slz12-dev-use2-security-rg)

.PARAMETER WorkspaceName
    Optional. The Log Analytics workspace name. Will auto-detect if not provided.

.PARAMETER SkipDataCheck
    Skip checking if data exists in tables before deploying rules

.PARAMETER WaitForData
    Wait up to 30 minutes for data to appear in tables before deploying rules

.EXAMPLE
    .\Finalize-SentinelDeployment.ps1 -ResourceGroupName "slz12-dev-use2-security-rg"

.EXAMPLE
    .\Finalize-SentinelDeployment.ps1 -ResourceGroupName "slz12-dev-use2-security-rg" -WaitForData

.NOTES
    Requires Azure CLI to be installed and logged in with appropriate permissions.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName,

    [switch]$SkipDataCheck,

    [switch]$WaitForData
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Microsoft Sentinel Post-Deployment Finalization" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Auto-detect workspace if not provided
if (-not $WorkspaceName) {
    Write-Host "INFO: Auto-detecting Log Analytics workspace..." -ForegroundColor Yellow
    $workspaces = az monitor log-analytics workspace list -g $ResourceGroupName --query "[].name" -o tsv 2>$null
    if (-not $workspaces) {
        Write-Error "No Log Analytics workspace found in resource group '$ResourceGroupName'"
        exit 1
    }
    $WorkspaceName = ($workspaces -split "`n")[0].Trim()
}
Write-Host "INFO: Using workspace: $WorkspaceName" -ForegroundColor Green

$subscriptionId = az account show --query id -o tsv
$workspaceId = az monitor log-analytics workspace show -g $ResourceGroupName -n $WorkspaceName --query customerId -o tsv

# Step 1: Verify Sentinel is enabled
Write-Host ""
Write-Host "Step 1: Verifying Microsoft Sentinel..." -ForegroundColor White
$sentinelSettings = az rest --method get --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/settings?api-version=2024-01-01-preview" 2>$null | ConvertFrom-Json

if ($sentinelSettings.value) {
    $settings = $sentinelSettings.value | ForEach-Object { $_.name }
    Write-Host "  Sentinel enabled with settings: $($settings -join ', ')" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Could not verify Sentinel settings" -ForegroundColor Yellow
}

# Step 2: Check data connectors
Write-Host ""
Write-Host "Step 2: Checking data connectors..." -ForegroundColor White
$connectors = az rest --method get --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/dataConnectors?api-version=2024-01-01-preview" 2>$null | ConvertFrom-Json

if ($connectors.value) {
    foreach ($connector in $connectors.value) {
        Write-Host "  - $($connector.name) ($($connector.kind))" -ForegroundColor Green
    }
} else {
    Write-Host "  No data connectors found" -ForegroundColor Yellow
}

# Step 3: Check for data in tables
Write-Host ""
Write-Host "Step 3: Checking data availability..." -ForegroundColor White

$tablesToCheck = @("AuditLogs", "SigninLogs", "AzureActivity")
$tablesWithData = @()

foreach ($table in $tablesToCheck) {
    try {
        $result = az monitor log-analytics query -w $workspaceId --analytics-query "$table | take 1" --timespan PT1H 2>$null | ConvertFrom-Json
        if ($result -and $result.Count -gt 0) {
            Write-Host "  - $table`: Data available" -ForegroundColor Green
            $tablesWithData += $table
        } else {
            Write-Host "  - $table`: No data yet" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  - $table`: Unable to query" -ForegroundColor Yellow
    }
}

# Wait for data if requested
if ($WaitForData -and $tablesWithData.Count -lt $tablesToCheck.Count) {
    Write-Host ""
    Write-Host "Waiting for data to appear (up to 30 minutes)..." -ForegroundColor Yellow
    
    $maxWaitMinutes = 30
    $waitIntervalSeconds = 60
    $waited = 0
    
    while ($tablesWithData.Count -lt $tablesToCheck.Count -and $waited -lt ($maxWaitMinutes * 60)) {
        Start-Sleep -Seconds $waitIntervalSeconds
        $waited += $waitIntervalSeconds
        
        Write-Host "  Checking... ($([math]::Floor($waited / 60)) minutes elapsed)" -ForegroundColor DarkGray
        
        foreach ($table in $tablesToCheck) {
            if ($table -notin $tablesWithData) {
                try {
                    $result = az monitor log-analytics query -w $workspaceId --analytics-query "$table | take 1" --timespan PT1H 2>$null | ConvertFrom-Json
                    if ($result -and $result.Count -gt 0) {
                        Write-Host "  - $table`: Data now available!" -ForegroundColor Green
                        $tablesWithData += $table
                    }
                } catch {}
            }
        }
    }
}

# Step 4: Deploy analytic rules
Write-Host ""
Write-Host "Step 4: Deploying analytic rules..." -ForegroundColor White

if (-not $SkipDataCheck -and $tablesWithData.Count -eq 0) {
    Write-Host "  SKIPPED: No data in tables yet. Run with -SkipDataCheck to force, or -WaitForData to wait." -ForegroundColor Yellow
} else {
    $scriptPath = Join-Path $PSScriptRoot "Deploy-AnalyticRules.ps1"
    if (Test-Path $scriptPath) {
        & $scriptPath -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName
    } else {
        Write-Host "  ERROR: Deploy-AnalyticRules.ps1 not found at $scriptPath" -ForegroundColor Red
    }
}

# Step 5: Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Finalization Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "Workspace: $WorkspaceName" -ForegroundColor White
Write-Host "Tables with data: $($tablesWithData.Count)/$($tablesToCheck.Count)" -ForegroundColor $(if ($tablesWithData.Count -eq $tablesToCheck.Count) { "Green" } else { "Yellow" })
Write-Host ""

if ($tablesWithData.Count -lt $tablesToCheck.Count) {
    Write-Host "TIP: Some tables don't have data yet. Re-run this script in 15-30 minutes" -ForegroundColor Yellow
    Write-Host "     or use -WaitForData to automatically wait for data to appear." -ForegroundColor Yellow
}
