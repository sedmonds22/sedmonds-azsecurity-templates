<#
.SYNOPSIS
Converts YAML analytic rule definitions to a single JSON manifest for deployment.

.DESCRIPTION
Reads all YAML files from the content/analytic-rules directory and generates a 
consolidated JSON file that can be used by deployment scripts.

.EXAMPLE
.\Convert-AnalyticRulesToJson.ps1
#>

[CmdletBinding()]
param(
    [string]$InputPath = (Join-Path $PSScriptRoot '..\content\analytic-rules'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\content\analytic-rules-manifest.json')
)

# Check for powershell-yaml module
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "Installing powershell-yaml module..."
    Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}
Import-Module powershell-yaml

$rules = @()
$yamlFiles = Get-ChildItem -Path $InputPath -Filter "*.yaml" -ErrorAction SilentlyContinue

foreach ($file in $yamlFiles) {
    try {
        $content = Get-Content -Path $file.FullName -Raw
        $yaml = ConvertFrom-Yaml -Yaml $content
        
        # Map YAML fields to ARM template properties
        $rule = @{
            id = if ($yaml.id) { $yaml.id } else { [guid]::NewGuid().ToString() }
            name = $yaml.name
            kind = if ($yaml.kind) { $yaml.kind } else { 'Scheduled' }
            description = if ($yaml.description) { $yaml.description.Trim() } else { '' }
            severity = if ($yaml.severity) { $yaml.severity } else { 'Medium' }
            enabled = if ($null -ne $yaml.enabled) { $yaml.enabled } else { $true }
            query = if ($yaml.query) { $yaml.query.Trim() } else { '' }
            queryFrequency = if ($yaml.queryFrequency) { "PT$($yaml.queryFrequency -replace 'h','H' -replace 'm','M' -replace 'd','D')" } else { 'PT5H' }
            queryPeriod = if ($yaml.queryPeriod) { "PT$($yaml.queryPeriod -replace 'h','H' -replace 'm','M' -replace 'd','D')" } else { 'PT5H' }
            triggerOperator = if ($yaml.triggerOperator) { $yaml.triggerOperator } else { 'GreaterThan' }
            triggerThreshold = if ($null -ne $yaml.triggerThreshold) { $yaml.triggerThreshold } else { 0 }
            tactics = if ($yaml.tactics) { $yaml.tactics } else { @() }
            techniques = if ($yaml.relevantTechniques) { $yaml.relevantTechniques } else { @() }
            entityMappings = if ($yaml.entityMappings) { $yaml.entityMappings } else { @() }
            sourceFile = $file.Name
        }
        
        # Only include rules with valid queries
        if ($rule.query -and $rule.name) {
            $rules += $rule
            Write-Verbose "Processed: $($file.Name)"
        } else {
            Write-Warning "Skipping $($file.Name): Missing name or query"
        }
    }
    catch {
        Write-Warning "Failed to process $($file.Name): $_"
    }
}

$manifest = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
    generatedAt = (Get-Date -Format 'o')
    ruleCount = $rules.Count
    rules = $rules
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "Generated manifest with $($rules.Count) rules at: $OutputPath"
