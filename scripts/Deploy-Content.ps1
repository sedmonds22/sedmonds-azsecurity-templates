<#
.SYNOPSIS
Deploys Microsoft Sentinel content solutions (Azure Activity and Microsoft Entra ID). Installs associated workbooks so they are available immediately in the workspace.

.DESCRIPTION
Invokes resource group scoped deployments for the packaged Content Hub solutions that
ship with Microsoft Sentinel. The script wraps `New-AzResourceGroupDeployment` with a
small amount of validation so the Azure Activity and Microsoft Entra ID solutions can
be installed consistently alongside the core infrastructure deployment. After the
solutions deploy, the script also publishes workbook JSON files and analytic rule YAML
definitions to the target workspace.

.EXAMPLE
PS> ./Deploy-Content.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' \
        -ResourceGroupName 'rg-sentinel-dev' -WorkspaceName 'law-sentinel-dev'

.PARAMETER SubscriptionId
Azure subscription identifier containing the Microsoft Sentinel workspace.

.PARAMETER ResourceGroupName
Resource group that hosts the Log Analytics workspace and Microsoft Sentinel.

.PARAMETER WorkspaceName
Name of the Log Analytics workspace where the content should be deployed.

.PARAMETER Solutions
Subset of solutions to deploy. Defaults to both Azure Activity and Microsoft Entra ID.

.PARAMETER ContentRoot
Path to the directory that contains the solution package templates.

.PARAMETER AzureActivityWorkbookName
Override for the primary Azure Activity workbook display name.

.PARAMETER AzureServiceHealthWorkbookName
Override for the Azure Service Health workbook display name.

.PARAMETER EntraAuditWorkbookName
Override for the Microsoft Entra ID audit workbook display name.

.PARAMETER EntraSigninWorkbookName
Override for the Microsoft Entra ID sign-in workbook display name.

.PARAMETER WorkbooksRoot
Path to the directory that contains workbook JSON definitions.

.PARAMETER SkipWorkbookDeployment
Switch to suppress workbook publishing if you only want the content templates installed.

.PARAMETER DeploymentNamePrefix
Prefix applied to generated deployment names when invoking ARM deployments.

.PARAMETER SkipAnalyticRuleDeployment
Skip publishing custom analytic rules from the local repository.

.PARAMETER AnalyticRulesRoot
Directory that contains analytic rule YAML definitions to publish.

.PARAMETER SkipHuntingQueryDeployment
Skip publishing custom hunting queries from the local repository.

.PARAMETER HuntingQueriesRoot
Directory that contains hunting query YAML definitions to publish.

.NOTES
Requires Az PowerShell modules (Az.Accounts, Az.Resources, Az.OperationalInsights).
Ensure you have Microsoft Sentinel Contributor permissions on the workspace.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter()]
    [ValidateSet('AzureActivity', 'MicrosoftEntraID')]
    [string[]]$Solutions = @('AzureActivity', 'MicrosoftEntraID'),

    [Parameter()]
    [string]$ContentRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\content\packages'),

    [Parameter()]
    [string]$AzureActivityWorkbookName = 'Azure Activity',

    [Parameter()]
    [string]$AzureServiceHealthWorkbookName = 'Azure Service Health Workbook',

    [Parameter()]
    [string]$EntraAuditWorkbookName = 'Microsoft Entra ID Audit logs',

    [Parameter()]
    [string]$EntraSigninWorkbookName = 'Microsoft Entra ID Sign-in logs',

    [Parameter()]
    [string]$WorkbooksRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\content\workbooks'),

    [Parameter()]
    [switch]$SkipWorkbookDeployment,

    [Parameter()]
    [string]$DeploymentNamePrefix = 'sentinel-content',

    [Parameter()]
    [switch]$SkipAnalyticRuleDeployment,

    [Parameter()]
    [string]$AnalyticRulesRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\content\analytic-rules'),

    [Parameter()]
    [string]$AnalyticRuleTemplatesRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\custom analytics\deploy'),

    [Parameter()]
    [switch]$SkipHuntingQueryDeployment,

    [Parameter()]
    [string]$HuntingQueriesRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\content\hunting-queries'),

    [Parameter()]
    [string]$SavedSearchApiVersion = '2020-08-01'
)

    function Get-DeterministicGuid {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Seed
        )

        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Seed))
        }
        finally {
            $md5.Dispose()
        }

        return [Guid]::new($hash).ToString()
    }

    function Publish-Workbook {
        param(
            [Parameter(Mandatory = $true)]
            [string]$SubscriptionId,

            [Parameter(Mandatory = $true)]
            [string]$ResourceGroupName,

            [Parameter(Mandatory = $true)]
            [string]$WorkspaceId,

            [Parameter(Mandatory = $true)]
            [string]$WorkspaceLocation,

            [Parameter(Mandatory = $true)]
            [hashtable]$Definition,

            [Parameter(Mandatory = $true)]
            [string]$WorkbooksRoot
        )

        $templatePath = Join-Path -Path $WorkbooksRoot -ChildPath $Definition.FileName
        if (-not (Test-Path -LiteralPath $templatePath)) {
            throw "Workbook template not found: $templatePath"
        }

        $serializedData = Get-Content -LiteralPath $templatePath -Raw
        $nameSeed = if ($Definition.ContainsKey('NameSeed') -and $Definition.NameSeed) { $Definition.NameSeed } else { $Definition.DisplayName }
        $resourceName = Get-DeterministicGuid -Seed ("{0}|{1}" -f $WorkspaceId, $nameSeed)

        $properties = [ordered]@{
            displayName    = $Definition.DisplayName
            serializedData = $serializedData
            version        = '1.0'
            sourceId       = $WorkspaceId
            category       = 'sentinel'
        }

        if ($Definition.ContainsKey('Description') -and $Definition.Description) {
            $properties['description'] = $Definition.Description
        }

        $body = [ordered]@{
            location   = $WorkspaceLocation
            kind       = 'shared'
            properties = $properties
            tags       = @{ 'hidden-title' = $Definition.DisplayName }
        }

        $payload = $body | ConvertTo-Json -Depth 20
        $path = "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Insights/workbooks/{2}?api-version=2021-08-01" -f $SubscriptionId, $ResourceGroupName, $resourceName

        Write-Verbose ("Publishing workbook '{0}' as resource '{1}'" -f $Definition.DisplayName, $resourceName)
        Invoke-AzRestMethod -Method PUT -Path $path -Payload $payload | Out-Null
    }

    function Convert-ToIsoDuration {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Duration
        )

        if ([string]::IsNullOrWhiteSpace($Duration)) {
            return $null
        }

        if ($Duration -match '^[Pp]') {
            return $Duration
        }

        if ($Duration -match '^(?<value>\d+)(?<unit>[smhdwSMHDW])$') {
            $numeric = [int]$matches.value
            switch ($matches.unit.ToLower()) {
                's' { return "PT{0}S" -f $numeric }
                'm' { return "PT{0}M" -f $numeric }
                'h' { return "PT{0}H" -f $numeric }
                'd' { return "P{0}D" -f $numeric }
                'w' { return "P{0}W" -f $numeric }
            }
        }

        return $Duration
    }

    function Convert-TriggerOperator {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Operator
        )

        if ([string]::IsNullOrWhiteSpace($Operator)) {
            return $null
        }

        $normalized = $Operator.ToLower()
        $map = @{
            'gt' = 'GreaterThan'
            'lt' = 'LessThan'
            'eq' = 'Equal'
            'ge' = 'GreaterThanOrEqual'
            'le' = 'LessThanOrEqual'
            'ne' = 'NotEqual'
        }

        if ($map.ContainsKey($normalized)) {
            return $map[$normalized]
        }

        return $Operator
    }

    function Deploy-AnalyticRuleTemplates {
        param(
            [Parameter(Mandatory = $true)]
            [string]$SubscriptionId,

            [Parameter(Mandatory = $true)]
            [string]$ResourceGroupName,

            [Parameter(Mandatory = $true)]
            [string]$WorkspaceName,

            [Parameter(Mandatory = $true)]
            [string]$RootPath,

            [Parameter()]
            [string]$DeploymentNamePrefix = 'custom-analytics',

            [Parameter()]
            [bool]$EnableRule = $true
        )

        if (-not (Test-Path -LiteralPath $RootPath)) {
            throw "Analytic rule template directory not found: $RootPath"
        }

        $templateFiles = Get-ChildItem -LiteralPath $RootPath -File -Filter '*.json' | Sort-Object -Property Name
        if (-not $templateFiles -or $templateFiles.Count -eq 0) {
            Write-Warning ("No analytic rule ARM templates found in '{0}'." -f $RootPath)
            return @()
        }

        $results = @()
        foreach ($file in $templateFiles) {
            $deploymentName = "{0}-{1}-{2}" -f $DeploymentNamePrefix, ($file.BaseName.ToLower()), (Get-Date -Format 'yyyyMMddHHmmss')
            Write-Verbose ("Deploying analytic rule template '{0}' via deployment '{1}'" -f $file.Name, $deploymentName)

            try {
                $deploymentParams = @{
                    Name                    = $deploymentName
                    ResourceGroupName       = $ResourceGroupName
                    TemplateFile            = $file.FullName
                    TemplateParameterObject = @{ workspaceName = $WorkspaceName; enableRule = $EnableRule }
                    Verbose                 = $true
                }

                $deployment = New-AzResourceGroupDeployment @deploymentParams
                $results += [pscustomobject]@{
                    Template     = $file.Name
                    Deployment   = $deploymentName
                    Provisioning = $deployment.ProvisioningState
                    Error        = $null
                }
            }
            catch {
                $results += [pscustomobject]@{
                    Template     = $file.Name
                    Deployment   = $deploymentName
                    Provisioning = 'Failed'
                    Error        = $_.Exception.Message
                }
                Write-Error ("Failed deploying analytic rule template '{0}': {1}" -f $file.Name, $_.Exception.Message)
            }
        }

        return $results
    }

    function ConvertTo-DeepPsObject {
        param(
            [Parameter()]
            $InputObject
        )

        if ($null -eq $InputObject) {
            return $null
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $ordered = [ordered]@{}
            foreach ($key in $InputObject.Keys) {
                $ordered[$key] = ConvertTo-DeepPsObject -InputObject $InputObject[$key]
            }
            return [pscustomobject]$ordered
        }

        if ($InputObject -is [System.Collections.IList] -and -not ($InputObject -is [System.Array] -and $InputObject.GetType().FullName -eq 'System.String[]')) {
            $list = @()
            foreach ($item in $InputObject) {
                $list += ConvertTo-DeepPsObject -InputObject $item
            }
            return ,$list
        }

        if ($InputObject -is [System.Array]) {
            $array = @()
            foreach ($element in $InputObject) {
                $array += ConvertTo-DeepPsObject -InputObject $element
            }
            return ,$array
        }

        return $InputObject
    }

    function Get-AnalyticRuleDefinitions {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RootPath
        )

        if (-not (Test-Path -LiteralPath $RootPath)) {
            throw "Analytic rules directory not found: $RootPath"
        }

        $files = Get-ChildItem -LiteralPath $RootPath -Filter '*.yaml' -File
        $rules = @()
        foreach ($file in $files) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            $definition = ConvertFrom-Yaml -Yaml $raw
            $definition = ConvertTo-DeepPsObject -InputObject $definition
            if (-not $definition) {
                Write-Warning "Unable to parse analytic rule definition: $($file.FullName)"
                continue
            }

            if (-not $definition.PSObject.Properties.Match('id')) {
                Write-Warning "Analytic rule definition missing 'id': $($file.FullName)"
                continue
            }

            $definition | Add-Member -MemberType NoteProperty -Name SourcePath -Value $file.FullName -Force
            $rules += $definition
        }

        return $rules
    }

    function ConvertTo-AnalyticRulePayload {
        param(
            [Parameter(Mandatory = $true)]
            [pscustomobject]$RuleDefinition
        )

        # Default to enabling rules when the YAML omits the flag so freshly deployed content is active immediately
        $enabled = if ($RuleDefinition.PSObject.Properties.Name -contains 'enabled') { [bool]$RuleDefinition.enabled } else { $true }
        $properties = [ordered]@{
            displayName = $RuleDefinition.name
            description = $RuleDefinition.description
            severity    = $RuleDefinition.severity
            enabled     = $enabled
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'status') {
            $properties['status'] = $RuleDefinition.status
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'query' -and $RuleDefinition.query) {
            $properties['query'] = $RuleDefinition.query
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'queryFrequency' -and $RuleDefinition.queryFrequency) {
            $properties['queryFrequency'] = Convert-ToIsoDuration -Duration $RuleDefinition.queryFrequency
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'queryPeriod' -and $RuleDefinition.queryPeriod) {
            $properties['queryPeriod'] = Convert-ToIsoDuration -Duration $RuleDefinition.queryPeriod
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'triggerOperator' -and $RuleDefinition.triggerOperator) {
            $properties['triggerOperator'] = Convert-TriggerOperator -Operator $RuleDefinition.triggerOperator
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'triggerThreshold') {
            $properties['triggerThreshold'] = [int]$RuleDefinition.triggerThreshold
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'tactics' -and $RuleDefinition.tactics) {
            $properties['tactics'] = @($RuleDefinition.tactics)
        }

        $techniqueSet = $null
        $subTechniqueSet = $null

        if ($RuleDefinition.PSObject.Properties.Name -contains 'relevantTechniques' -and $RuleDefinition.relevantTechniques) {
            $techniqueSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $subTechniqueSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($technique in @($RuleDefinition.relevantTechniques)) {
                if ([string]::IsNullOrWhiteSpace($technique)) { continue }

                $trimmedTechnique = $technique.Trim()
                if ($trimmedTechnique -match '^(T\d{4})\.(\d{3})$') {
                    [void]$techniqueSet.Add($matches[1])
                    [void]$subTechniqueSet.Add($trimmedTechnique)
                }
                elseif ($trimmedTechnique -match '^T\d{4}$') {
                    [void]$techniqueSet.Add($trimmedTechnique)
                }
                else {
                    [void]$techniqueSet.Add($trimmedTechnique)
                }
            }
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'subTechniques' -and $RuleDefinition.subTechniques) {
            if (-not $subTechniqueSet) {
                $subTechniqueSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            }

            foreach ($subTechnique in @($RuleDefinition.subTechniques)) {
                if ([string]::IsNullOrWhiteSpace($subTechnique)) { continue }

                $trimmedSubTechnique = $subTechnique.Trim()
                [void]$subTechniqueSet.Add($trimmedSubTechnique)

                if ($trimmedSubTechnique -match '^(T\d{4})\.(\d{3})$') {
                    if (-not $techniqueSet) {
                        $techniqueSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                    }
                    [void]$techniqueSet.Add($matches[1])
                }
            }
        }

        if ($techniqueSet -and $techniqueSet.Count -gt 0) {
            $properties['techniques'] = @($techniqueSet)
        }

        if ($subTechniqueSet -and $subTechniqueSet.Count -gt 0) {
            $properties['subTechniques'] = @($subTechniqueSet)
        }

        $hasSuppressionDuration = $false
        if ($RuleDefinition.PSObject.Properties.Name -contains 'suppressionDuration' -and $RuleDefinition.suppressionDuration) {
            $properties['suppressionDuration'] = Convert-ToIsoDuration -Duration $RuleDefinition.suppressionDuration
            $hasSuppressionDuration = $true
        }

        $hasSuppressionEnabled = $false
        if ($RuleDefinition.PSObject.Properties.Name -contains 'suppressionEnabled') {
            $properties['suppressionEnabled'] = [bool]$RuleDefinition.suppressionEnabled
            $hasSuppressionEnabled = $true
        }

        if (-not $hasSuppressionDuration) {
            # Azure Sentinel Scheduled alert rules require a suppression duration even when suppression is disabled.
            $properties['suppressionDuration'] = 'PT5M'
        }

        if (-not $hasSuppressionEnabled) {
            $properties['suppressionEnabled'] = $false
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'requiredDataConnectors' -and $RuleDefinition.requiredDataConnectors) {
            $connectors = @()
            foreach ($connector in $RuleDefinition.requiredDataConnectors) {
                $connectors += @{ connectorId = $connector.connectorId; dataTypes = @($connector.dataTypes) }
            }
            $properties['requiredDataConnectors'] = $connectors
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'entityMappings' -and $RuleDefinition.entityMappings) {
            $properties['entityMappings'] = @($RuleDefinition.entityMappings)
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'customDetails' -and $RuleDefinition.customDetails) {
            $properties['customDetails'] = $RuleDefinition.customDetails
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'alertDetailsOverride' -and $RuleDefinition.alertDetailsOverride) {
            $properties['alertDetailsOverride'] = $RuleDefinition.alertDetailsOverride
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'incidentConfiguration' -and $RuleDefinition.incidentConfiguration) {
            $properties['incidentConfiguration'] = $RuleDefinition.incidentConfiguration
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'eventGroupingSettings' -and $RuleDefinition.eventGroupingSettings) {
            $properties['eventGroupingSettings'] = $RuleDefinition.eventGroupingSettings
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'templateVersion' -and $RuleDefinition.templateVersion) {
            $properties['alertRuleTemplateVersion'] = $RuleDefinition.templateVersion
        } elseif ($RuleDefinition.PSObject.Properties.Name -contains 'version' -and $RuleDefinition.version) {
            $properties['alertRuleTemplateVersion'] = $RuleDefinition.version
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'alertRuleTemplateName' -and $RuleDefinition.alertRuleTemplateName) {
            $properties['alertRuleTemplateName'] = $RuleDefinition.alertRuleTemplateName
        }

        if ($RuleDefinition.PSObject.Properties.Name -contains 'tags' -and $RuleDefinition.tags) {
            $properties['tags'] = @($RuleDefinition.tags)
        }

        $kind = if ($RuleDefinition.PSObject.Properties.Name -contains 'kind' -and $RuleDefinition.kind) { $RuleDefinition.kind } else { 'Scheduled' }

        return [ordered]@{
            kind       = $kind
            properties = $properties
        }
    }

    function Publish-AnalyticRule {
        param(
            [Parameter(Mandatory = $true)]
            [string]$SubscriptionId,

            [Parameter(Mandatory = $true)]
            [string]$ResourceGroupName,

            [Parameter(Mandatory = $true)]
            [string]$WorkspaceName,

            [Parameter(Mandatory = $true)]
            [pscustomobject]$RuleDefinition
        )

        $payload = ConvertTo-AnalyticRulePayload -RuleDefinition $RuleDefinition
        $json = $payload | ConvertTo-Json -Depth 30
        $path = "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.OperationalInsights/workspaces/{2}/providers/Microsoft.SecurityInsights/alertRules/{3}?api-version=2024-01-01-preview" -f $SubscriptionId, $ResourceGroupName, $WorkspaceName, $RuleDefinition.id

        Write-Verbose ("Publishing analytic rule '{0}' ({1})" -f $RuleDefinition.name, $RuleDefinition.id)
        $response = Invoke-AzRestMethod -Method PUT -Path $path -Payload $json

        $statusCode = $null
        if ($response) {
            if ($response.PSObject.Properties.Name -contains 'StatusCode') {
                $statusCode = $response.StatusCode
            }
            elseif ($response.PSObject.Properties.Name -contains 'statusCode') {
                $statusCode = $response.statusCode
            }
            elseif ($response.PSObject.Properties.Name -contains 'Content') {
                $content = $response.Content
                if ($content -and $content.PSObject.Properties.Name -contains 'statusCode') {
                    $statusCode = $content.statusCode
                }
            }
        }
        
        $isEnabled = $false
        if ($payload.properties -and $payload.properties.Keys -contains 'enabled') {
            $isEnabled = [bool]$payload.properties['enabled']
        }

        return [pscustomobject]@{
            RuleId      = $RuleDefinition.id
            DisplayName = $RuleDefinition.name
            Enabled     = $isEnabled
            HttpStatus  = $statusCode
        }
    }

    function Get-HuntingQueryDefinitions {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RootPath
        )

        if (-not (Test-Path -LiteralPath $RootPath)) {
            throw "Hunting queries directory not found: $RootPath"
        }

        $files = Get-ChildItem -LiteralPath $RootPath -Filter '*.yaml' -File
        $queries = @()
        foreach ($file in $files) {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
            $definition = ConvertFrom-Yaml -Yaml $raw
            $definition = ConvertTo-DeepPsObject -InputObject $definition
            if (-not $definition) {
                Write-Warning "Unable to parse hunting query definition: $($file.FullName)"
                continue
            }

            if (-not $definition.PSObject.Properties.Match('id')) {
                Write-Warning "Hunting query definition missing 'id': $($file.FullName)"
                continue
            }

            if (-not $definition.PSObject.Properties.Match('query')) {
                Write-Warning "Hunting query definition missing 'query': $($file.FullName)"
                continue
            }

            $definition | Add-Member -MemberType NoteProperty -Name SourcePath -Value $file.FullName -Force
            $queries += $definition
        }

        return $queries
    }

    function ConvertTo-SavedSearchTags {
        param(
            [Parameter()]
            [pscustomobject]$Definition
        )

        $tags = @()

        if ($Definition -and ($Definition.PSObject.Properties.Name -contains 'severity') -and $Definition.severity) {
            $tags += @{ name = 'severity'; value = [string]$Definition.severity }
        }

        if ($Definition -and ($Definition.PSObject.Properties.Name -contains 'tactics') -and $Definition.tactics) {
            foreach ($tactic in @($Definition.tactics)) {
                if ($tactic) {
                    $tags += @{ name = 'tactic'; value = [string]$tactic }
                }
            }
        }

        if ($Definition -and ($Definition.PSObject.Properties.Name -contains 'relevantTechniques') -and $Definition.relevantTechniques) {
            foreach ($technique in @($Definition.relevantTechniques)) {
                if ($technique) {
                    $tags += @{ name = 'technique'; value = [string]$technique }
                }
            }
        }

        if ($Definition -and ($Definition.PSObject.Properties.Name -contains 'version') -and $Definition.version) {
            $tags += @{ name = 'version'; value = [string]$Definition.version }
        }

        return $tags
    }

    function Publish-HuntingQuerySavedSearch {
        param(
            [Parameter(Mandatory = $true)]
            [string]$SubscriptionId,

            [Parameter(Mandatory = $true)]
            [string]$ResourceGroupName,

            [Parameter(Mandatory = $true)]
            [string]$WorkspaceName,

            [Parameter(Mandatory = $true)]
            [pscustomobject]$QueryDefinition,

            [Parameter(Mandatory = $true)]
            [string]$ApiVersion
        )

        $savedSearchName = [string]$QueryDefinition.id
        $displayName = if ($QueryDefinition.PSObject.Properties.Name -contains 'name' -and $QueryDefinition.name) { [string]$QueryDefinition.name } else { $savedSearchName }
        $category = 'Hunting Queries'

        $properties = [ordered]@{
            displayName = $displayName
            category    = $category
            query       = [string]$QueryDefinition.query
            version     = if ($QueryDefinition.PSObject.Properties.Name -contains 'version' -and $QueryDefinition.version) { [string]$QueryDefinition.version } else { '1.0' }
        }

        if ($QueryDefinition.PSObject.Properties.Name -contains 'description' -and $QueryDefinition.description) {
            $properties['description'] = [string]$QueryDefinition.description
        }

        $tagList = ConvertTo-SavedSearchTags -Definition $QueryDefinition
        if ($tagList.Count -gt 0) {
            $properties['tags'] = $tagList
        }

        $payload = [ordered]@{ properties = $properties } | ConvertTo-Json -Depth 20
        $path = "/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.OperationalInsights/workspaces/{2}/savedSearches/{3}?api-version={4}" -f $SubscriptionId, $ResourceGroupName, $WorkspaceName, $savedSearchName, $ApiVersion

        Write-Verbose ("Publishing hunting query saved search '{0}' ({1})" -f $displayName, $savedSearchName)
        $response = Invoke-AzRestMethod -Method PUT -Path $path -Payload $payload

        $statusCode = $null
        if ($response) {
            if ($response.PSObject.Properties.Name -contains 'StatusCode') {
                $statusCode = $response.StatusCode
            }
            elseif ($response.PSObject.Properties.Name -contains 'statusCode') {
                $statusCode = $response.statusCode
            }
        }

        return [pscustomobject]@{
            QueryId     = $savedSearchName
            DisplayName = $displayName
            Category    = $category
            HttpStatus  = $statusCode
        }
    }

$requiredModules = 'Az.Accounts', 'Az.Resources', 'Az.OperationalInsights'
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Required module '$module' is not installed. Install-Module $module -Scope CurrentUser"
    }
}

$yamlCmdletAvailable = [bool](Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue)
if (-not $yamlCmdletAvailable) {
    Write-Warning 'ConvertFrom-Yaml cmdlet not available. YAML analytic rules and hunting queries will be skipped. Analytic rules will be deployed from ARM templates under custom analytics/deploy instead.'
    $SkipHuntingQueryDeployment = $true
}

Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null

$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop
# Some Az.OperationalInsights versions populate Id while others only expose ResourceId, so fall back gracefully.
$workspaceResourceId = if ($workspace.PSObject.Properties.Name -contains 'Id' -and $workspace.Id) { $workspace.Id } else { $workspace.ResourceId }
$workspaceLocation = $workspace.Location

$solutionMap = @{
    AzureActivity    = @{
        TemplatePath = Join-Path -Path $ContentRoot -ChildPath 'azure-activity\mainTemplate.json'
        ParameterBuilder = {
            param($common)
                $common['workbook1-name'] = $AzureActivityWorkbookName
                $common['workbook2-name'] = $AzureServiceHealthWorkbookName
            return $common
        }
    }
    MicrosoftEntraID = @{
        TemplatePath = Join-Path -Path $ContentRoot -ChildPath 'microsoft-entra-id\mainTemplate.json'
        ParameterBuilder = {
            param($common)
                $common['workbook1-name'] = $EntraAuditWorkbookName
                $common['workbook2-name'] = $EntraSigninWorkbookName
            return $common
        }
    }
}

$workbookCatalog = @{
    AzureActivity = @(
        @{ FileName = 'AzureActivity.json'; DisplayName = $AzureActivityWorkbookName; NameSeed = 'AzureActivity' }
        @{ FileName = 'AzureServiceHealthWorkbook.json'; DisplayName = $AzureServiceHealthWorkbookName; NameSeed = 'AzureServiceHealth' }
    )
    MicrosoftEntraID = @(
        @{ FileName = 'AzureActiveDirectoryAuditLogs.json'; DisplayName = $EntraAuditWorkbookName; NameSeed = 'EntraAuditLogs' }
        @{ FileName = 'AzureActiveDirectorySignins.json'; DisplayName = $EntraSigninWorkbookName; NameSeed = 'EntraSigninLogs' }
    )
}

$deployments = @()
$workbooksToPublish = @()
foreach ($solution in $Solutions) {
    if (-not $solutionMap.ContainsKey($solution)) {
        Write-Warning "Solution '$solution' is not recognised. Skipping."
        continue
    }

    $templatePath = $solutionMap[$solution].TemplatePath
    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Template file not found: $templatePath"
    }

    $commonParameters = @{
        workspace            = $WorkspaceName
        'workspace-location' = $workspaceLocation
    }

    $parameterObject = & $solutionMap[$solution].ParameterBuilder $commonParameters

    $deploymentName = "{0}-{1}-{2}" -f $DeploymentNamePrefix, $solution.ToLower(), (Get-Date -Format 'yyyyMMddHHmmss')

    $deploymentParams = @{
        Name                   = $deploymentName
        ResourceGroupName      = $ResourceGroupName
        TemplateFile           = $templatePath
        TemplateParameterObject = $parameterObject
        Verbose                = $true
    }

    Write-Verbose ("Starting deployment '{0}' for solution '{1}'" -f $deploymentName, $solution)
    $result = New-AzResourceGroupDeployment @deploymentParams
    $deployments += [pscustomobject]@{
        Solution       = $solution
        DeploymentName = $deploymentName
        Provisioning   = $result.ProvisioningState
    }

    if ($workbookCatalog.ContainsKey($solution)) {
        $workbooksToPublish += $workbookCatalog[$solution]
    }
}

if (-not $workspaceResourceId) {
    throw "Unable to determine workspace resource ID."
}

if (-not $SkipWorkbookDeployment.IsPresent -and $workbooksToPublish.Count -gt 0) {
    Write-Verbose ("Publishing {0} workbook(s) to workspace '{1}'" -f $workbooksToPublish.Count, $WorkspaceName)
    foreach ($workbookDefinition in $workbooksToPublish) {
        Publish-Workbook -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceId $workspaceResourceId -WorkspaceLocation $workspaceLocation -Definition $workbookDefinition -WorkbooksRoot $WorkbooksRoot
    }
}

$analyticRuleResults = @()
if (-not $SkipAnalyticRuleDeployment.IsPresent) {
    if ($yamlCmdletAvailable) {
        $analyticRules = Get-AnalyticRuleDefinitions -RootPath $AnalyticRulesRoot

        if ($analyticRules.Count -eq 0) {
            Write-Warning ("No analytic rule definitions found in '{0}'." -f $AnalyticRulesRoot)
        }
        else {
            Write-Verbose ("Publishing {0} analytic rule(s) to workspace '{1}'" -f $analyticRules.Count, $WorkspaceName)
            foreach ($rule in $analyticRules) {
                try {
                    $publishResult = Publish-AnalyticRule -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -RuleDefinition $rule
                    $analyticRuleResults += $publishResult
                }
                catch {
                    $analyticRuleResults += [pscustomobject]@{
                        RuleId      = if ($rule.PSObject.Properties.Name -contains 'id') { $rule.id } else { $null }
                        DisplayName = if ($rule.PSObject.Properties.Name -contains 'name') { $rule.name } else { $null }
                        Enabled     = if ($rule.PSObject.Properties.Name -contains 'enabled') { [bool]$rule.enabled } else { $false }
                        HttpStatus  = $null
                        Error       = $_.Exception.Message
                    }
                    Write-Error ("Failed to publish analytic rule '{0}': {1}" -f $rule.name, $_.Exception.Message)
                }
            }

            $failureCount = ($analyticRuleResults | Where-Object { $_.PSObject.Properties.Name -contains 'Error' -and $_.Error }).Count
            $successCount = $analyticRuleResults.Count - $failureCount
            Write-Verbose ("Analytic rule publication complete. Success: {0}, Failed: {1}" -f $successCount, $failureCount)
        }
    }
    else {
        Write-Verbose ("Deploying analytic rules from ARM templates in '{0}'" -f $AnalyticRuleTemplatesRoot)
        $analyticRuleResults = Deploy-AnalyticRuleTemplates -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -RootPath $AnalyticRuleTemplatesRoot -DeploymentNamePrefix $DeploymentNamePrefix
    }
}

$huntingQueryResults = @()
if (-not $SkipHuntingQueryDeployment.IsPresent) {
    $huntingQueries = Get-HuntingQueryDefinitions -RootPath $HuntingQueriesRoot

    if ($huntingQueries.Count -eq 0) {
        Write-Warning ("No hunting query definitions found in '{0}'." -f $HuntingQueriesRoot)
    }
    else {
        Write-Verbose ("Publishing {0} hunting query(ies) to workspace '{1}'" -f $huntingQueries.Count, $WorkspaceName)
        foreach ($queryDefinition in $huntingQueries) {
            try {
                $publishResult = Publish-HuntingQuerySavedSearch -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -QueryDefinition $queryDefinition -ApiVersion $SavedSearchApiVersion
                $huntingQueryResults += $publishResult
            }
            catch {
                $huntingQueryResults += [pscustomobject]@{
                    QueryId     = if ($queryDefinition.PSObject.Properties.Name -contains 'id') { [string]$queryDefinition.id } else { $null }
                    DisplayName = if ($queryDefinition.PSObject.Properties.Name -contains 'name') { [string]$queryDefinition.name } else { $null }
                    Category    = 'Hunting Queries'
                    HttpStatus  = $null
                    Error       = $_.Exception.Message
                }
                Write-Error ("Failed to publish hunting query '{0}': {1}" -f $queryDefinition.name, $_.Exception.Message)
            }
        }

        $failureCount = ($huntingQueryResults | Where-Object { $_.PSObject.Properties.Name -contains 'Error' -and $_.Error }).Count
        $successCount = $huntingQueryResults.Count - $failureCount
        Write-Verbose ("Hunting query publication complete. Success: {0}, Failed: {1}" -f $successCount, $failureCount)
    }
}

return [pscustomobject]@{
    Deployments        = $deployments
    AnalyticRuleResults = $analyticRuleResults
    HuntingQueryResults = $huntingQueryResults
}
