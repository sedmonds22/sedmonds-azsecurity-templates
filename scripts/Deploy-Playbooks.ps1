<#!
.SYNOPSIS
Deploys Microsoft Sentinel response playbooks and assigns required permissions.

.DESCRIPTION
Deploys Logic Apps sourced from the Microsoft Entra ID solution (Block-AADUser, Prompt-User,
Reset-AADUserPassword, Revoke-AADSignInSessions). The script wraps `New-AzResourceGroupDeployment`
for the provided ARM templates, optionally renames playbooks, and assigns the Microsoft
Sentinel Responder role to the playbook managed identities so they can update incidents.

After deployment, the script outputs the playbooks and any role assignments created. You must
still grant Microsoft Graph API permissions and authorise Logic App connections as noted in the
upstream playbook documentation.

.EXAMPLE
PS> ./Deploy-Playbooks.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ResourceGroupName 'rg-sentinel-dev' -WorkspaceName 'law-sentinel-dev' `
        -AssignSentinelResponder

.PARAMETER SubscriptionId
Azure subscription identifier that hosts the Log Analytics workspace and playbooks.

.PARAMETER ResourceGroupName
Resource group where playbooks should be deployed.

.PARAMETER WorkspaceName
Log Analytics workspace name used for Microsoft Sentinel (used for role assignment scope).

.PARAMETER Playbooks
Names of the playbooks to deploy. Defaults to all available playbooks.

.PARAMETER PlaybookNameOverrides
Hashtable mapping playbook keys to desired Logic App names.

.PARAMETER PlaybooksRoot
Root folder containing playbook ARM templates (defaults to repository content path).

.PARAMETER DeploymentNamePrefix
Prefix used when generating ARM deployment names.

.PARAMETER AssignSentinelResponder
Switch that triggers Microsoft Sentinel Responder role assignment to the playbook identities.

.NOTES
Requires Az modules: Accounts, Resources, OperationalInsights, LogicApp.
The executing principal must be able to deploy resources and assign roles at the workspace scope.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter()]
    [ValidateSet('Block-AADUser','Prompt-User','Reset-AADUserPassword','Revoke-AADSignInSessions')]
    [string[]]$Playbooks = @('Block-AADUser','Prompt-User','Reset-AADUserPassword','Revoke-AADSignInSessions'),

    [Parameter()]
    [hashtable]$PlaybookNameOverrides = @{},

    [Parameter()]
    [string]$TeamsId,

    [Parameter()]
    [string]$TeamsChannelId,

    [Parameter()]
    [string]$PlaybooksRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\content\playbooks'),

    [Parameter()]
    [string]$DeploymentNamePrefix = 'sentinel-playbook',

    [Parameter()]
    [switch]$AssignSentinelResponder
)

$requiredModules = 'Az.Accounts', 'Az.Resources', 'Az.OperationalInsights', 'Az.LogicApp'
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Required module '$module' is not installed. Install-Module $module -Scope CurrentUser"
    }
}

Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction Stop
$workspaceResourceId = $workspace.Id

$playbookCatalog = @{
    'Block-AADUser' = @{
        TemplatePath = Join-Path -Path $PlaybooksRoot -ChildPath 'Block-AADUser\incident-trigger\azuredeploy.json'
        DefaultName = 'Block-EntraIDUser-Incident'
    }
    'Prompt-User' = @{
        TemplatePath = Join-Path -Path $PlaybooksRoot -ChildPath 'Prompt-User\incident-trigger\azuredeploy.json'
        DefaultName = 'Prompt-EntraIDUser-Incident'
    }
    'Reset-AADUserPassword' = @{
        TemplatePath = Join-Path -Path $PlaybooksRoot -ChildPath 'Reset-AADUserPassword\incident-trigger\azuredeploy.json'
        DefaultName = 'Reset-EntraIDUserPassword-Incident'
    }
    'Revoke-AADSignInSessions' = @{
        TemplatePath = Join-Path -Path $PlaybooksRoot -ChildPath 'Revoke-AADSignInSessions\incident-trigger\azuredeploy.json'
        DefaultName = 'Revoke-EntraIDSignInSessions-Incident'
    }
}

$results = @()

foreach ($playbook in $Playbooks) {
    if (-not $playbookCatalog.ContainsKey($playbook)) {
        Write-Warning "Playbook '$playbook' is not recognised. Skipping."
        continue
    }

    $definition = $playbookCatalog[$playbook]
    $templatePath = $definition.TemplatePath

    if (-not (Test-Path -LiteralPath $templatePath)) {
        throw "Template file not found: $templatePath"
    }

    $playbookName = if ($PlaybookNameOverrides.ContainsKey($playbook)) {
        [string]$PlaybookNameOverrides[$playbook]
    } else {
        $definition.DefaultName
    }

    $parameters = @{
        PlaybookName = $playbookName
    }

    if ($playbook -eq 'Prompt-User') {
        if (-not $TeamsId) {
            throw "Parameter TeamsId is required when deploying the 'Prompt-User' playbook."
        }

        if (-not $TeamsChannelId) {
            throw "Parameter TeamsChannelId is required when deploying the 'Prompt-User' playbook."
        }

        $parameters['TeamsId'] = $TeamsId
        $parameters['TeamsChannelId'] = $TeamsChannelId
    }

    $deploymentName = "{0}-{1}-{2}" -f $DeploymentNamePrefix, ($playbook.ToLower() -replace '[^a-z0-9-]',''), (Get-Date -Format 'yyyyMMddHHmmss')

    Write-Verbose ("Deploying playbook '{0}' using template '{1}'" -f $playbookName, $templatePath)
    $deploymentResult = New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $templatePath -TemplateParameterObject $parameters -Verbose:$false -ErrorAction Stop

    $roleAssignmentId = $null
    if ($AssignSentinelResponder.IsPresent) {
        $logicApp = Get-AzLogicApp -ResourceGroupName $ResourceGroupName -Name $playbookName -ErrorAction Stop
        $principalId = $logicApp.Identity.PrincipalId

        if ($principalId) {
            $existingAssignment = Get-AzRoleAssignment -ObjectId $principalId -Scope $workspaceResourceId -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq 'Microsoft Sentinel Responder' }
            if (-not $existingAssignment) {
                $assignment = New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Microsoft Sentinel Responder' -Scope $workspaceResourceId -ErrorAction Stop
                $roleAssignmentId = $assignment.Id
            } else {
                $roleAssignmentId = $existingAssignment.Id
            }
        } else {
            Write-Warning "Playbook '$playbookName' does not expose a managed identity. Role assignment skipped."
        }
    }

    $results += [pscustomobject]@{
        Playbook           = $playbook
        LogicAppName       = $playbookName
        DeploymentName     = $deploymentName
        ProvisioningState  = $deploymentResult.ProvisioningState
        RoleAssignmentId   = $roleAssignmentId
    }
}

Write-Verbose 'Playbook deployment complete.'
return $results
