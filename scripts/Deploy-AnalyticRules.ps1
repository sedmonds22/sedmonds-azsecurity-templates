<#
.SYNOPSIS
    Post-deployment script to deploy Microsoft Sentinel analytic rules after data connectors have populated tables.

.DESCRIPTION
    This script should be run 15-30 minutes after the initial MLZ Sentinel deployment to allow 
    data connectors time to populate Log Analytics tables. The analytic rules require data in 
    the tables (AuditLogs, SigninLogs, AzureActivity, etc.) to pass validation.

.PARAMETER ResourceGroupName
    The resource group containing the Sentinel workspace (e.g., slz12-dev-use2-security-rg)

.PARAMETER WorkspaceName
    The Log Analytics workspace name where Sentinel is enabled

.PARAMETER ManifestUrl
    URL to the analytic rules manifest JSON file. Defaults to the GitHub raw URL.

.PARAMETER WhatIf
    Show what rules would be created without actually creating them

.EXAMPLE
    .\Deploy-AnalyticRules.ps1 -ResourceGroupName "slz12-dev-use2-security-rg" -WorkspaceName "law-slz12-dev-use2-security"

.EXAMPLE
    .\Deploy-AnalyticRules.ps1 -ResourceGroupName "slz12-dev-use2-security-rg" -WorkspaceName "law-slz12-dev-use2-security" -WhatIf

.NOTES
    Requires Azure CLI to be installed and logged in with appropriate permissions (Microsoft Sentinel Contributor).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $false)]
    [string]$ManifestUrl = 'https://raw.githubusercontent.com/sedmonds22/sedmonds-azsecurity-templates/main/content/analytic-rules-manifest.json'
)

$ErrorActionPreference = 'Stop'

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Microsoft Sentinel Analytic Rules Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Auto-detect workspace if not provided
if (-not $WorkspaceName) {
    Write-Host "INFO: Auto-detecting Log Analytics workspace in $ResourceGroupName..." -ForegroundColor Yellow
    $workspaces = az monitor log-analytics workspace list -g $ResourceGroupName --query "[].name" -o tsv 2>$null
    if (-not $workspaces) {
        Write-Error "No Log Analytics workspace found in resource group '$ResourceGroupName'"
        exit 1
    }
    $WorkspaceName = ($workspaces -split "`n")[0].Trim()
    Write-Host "INFO: Using workspace: $WorkspaceName" -ForegroundColor Green
}

# Get subscription ID
$subscriptionId = az account show --query id -o tsv

# Fetch the manifest
Write-Host "INFO: Fetching analytic rules manifest from $ManifestUrl" -ForegroundColor Yellow
try {
    $manifest = Invoke-RestMethod -Uri $ManifestUrl -ErrorAction Stop
} catch {
    Write-Error "Failed to fetch manifest: $_"
    exit 1
}

$ruleCount = $manifest.ruleCount
Write-Host "INFO: Found $ruleCount rules to deploy" -ForegroundColor Green
Write-Host ""

$successCount = 0
$skipCount = 0
$errorCount = 0
$apiVersion = "2024-01-01-preview"

foreach ($rule in $manifest.rules) {
    $ruleId = $rule.id
    $ruleName = $rule.name
    $kind = $rule.kind

    $resourceUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/providers/Microsoft.SecurityInsights/alertRules/${ruleId}?api-version=$apiVersion"

    # Check if rule already exists
    $existingRule = $null
    try {
        $existingRule = az rest --method get --url $resourceUrl --only-show-errors 2>$null | ConvertFrom-Json
    } catch {
        # Rule doesn't exist, continue
    }

    if ($existingRule) {
        Write-Host "SKIP: Rule '$ruleName' already exists" -ForegroundColor DarkGray
        $skipCount++
        continue
    }

    # Build payload based on rule kind
    if ($kind -eq "NRT") {
        $payload = @{
            kind = "NRT"
            properties = @{
                displayName = $rule.name
                description = $rule.description
                enabled = $rule.enabled
                severity = $rule.severity
                query = $rule.query
                tactics = $rule.tactics
                techniques = $rule.techniques
                entityMappings = $rule.entityMappings
                suppressionDuration = "PT5H"
                suppressionEnabled = $false
            }
        }
    } else {
        $payload = @{
            kind = "Scheduled"
            properties = @{
                displayName = $rule.name
                description = $rule.description
                enabled = $rule.enabled
                severity = $rule.severity
                query = $rule.query
                queryFrequency = $rule.queryFrequency
                queryPeriod = $rule.queryPeriod
                triggerOperator = $rule.triggerOperator
                triggerThreshold = $rule.triggerThreshold
                tactics = $rule.tactics
                techniques = $rule.techniques
                entityMappings = $rule.entityMappings
                suppressionDuration = "PT5H"
                suppressionEnabled = $false
            }
        }
    }

    if ($WhatIf -or $PSCmdlet.ShouldProcess($ruleName, "Create analytic rule")) {
        if ($WhatIf) {
            Write-Host "WHATIF: Would create rule '$ruleName' ($kind)" -ForegroundColor Magenta
            $successCount++
            continue
        }

        # Write payload to temp file
        $payloadJson = $payload | ConvertTo-Json -Depth 10 -Compress
        $tempFile = [System.IO.Path]::GetTempFileName()
        $payloadJson | Out-File -FilePath $tempFile -Encoding utf8 -NoNewline

        try {
            $response = az rest --method put --url $resourceUrl --body "@$tempFile" --headers "Content-Type=application/json" --only-show-errors 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "SUCCESS: Created rule '$ruleName'" -ForegroundColor Green
                $successCount++
            } else {
                $responseStr = $response -join " "
                if ($responseStr -match "BadRequest|data connector|table.*not found|table does not exist|semantic error") {
                    Write-Host "SKIP: Rule '$ruleName' - required data not available yet" -ForegroundColor Yellow
                    $skipCount++
                } else {
                    Write-Host "ERROR: Failed to create rule '$ruleName': $responseStr" -ForegroundColor Red
                    $errorCount++
                }
            }
        } catch {
            Write-Host "ERROR: Failed to create rule '$ruleName': $_" -ForegroundColor Red
            $errorCount++
        } finally {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Analytic Rules Deployment Summary:" -ForegroundColor Cyan
Write-Host "  Total rules: $ruleCount" -ForegroundColor White
Write-Host "  Successfully created: $successCount" -ForegroundColor Green
Write-Host "  Skipped (existing/no data): $skipCount" -ForegroundColor Yellow
Write-Host "  Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "White" })
Write-Host "==========================================" -ForegroundColor Cyan

if ($skipCount -gt 0 -and $errorCount -eq 0) {
    Write-Host ""
    Write-Host "TIP: Some rules were skipped because required data tables don't have data yet." -ForegroundColor Yellow
    Write-Host "     Run this script again in 15-30 minutes after data starts flowing." -ForegroundColor Yellow
}

exit $(if ($errorCount -gt 0) { 1 } else { 0 })
