# Mission Landing Zone

[**Home**](./README.md) | [**Design**](./docs/design.md) | [**Add-Ons**](./src/add-ons/README.md) | [**Resources**](./docs/resources.md)

## Deploy to Azure

| Cloud  | Deployment Button |
| :----- | :----- |
| Azure Commercial | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#blade/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fmlz%2Fsrc%2Fmlz.json%3Fv%3Dcc9f559/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fmlz%2Fsrc%2Fmlz.uiDefinition.json%3Fv%3Dcc9f559) |
| Azure Government |  [![Deploy to Azure Gov](https://aka.ms/deploytoazuregovbutton)](https://portal.azure.us/#blade/Microsoft_Azure_CreateUIDef/CustomDeploymentBlade/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fmlz%2Fsrc%2Fmlz.json%3Fv%3Dcc9f559/uiFormDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fsedmonds22%2Fsedmonds-azsecurity-templates%2Fmain%2Fmlz%2Fsrc%2Fmlz.uiDefinition.json%3Fv%3Dcc9f559) |

Mission Landing Zone is a highly opinionated infrastructure as code (IaC) template. IT oversight organizations can use the template to create a cloud management system to deploy Azure environments for their workloads and teams. The solution addresses a narrowly scoped, specific need for a [Secure Cloud Computing Architecture (SCCA)](docs/scca.md) compliant hub and spoke infrastructure.
- Designed for US Government mission customers
- Implements controls following Microsoft's [SACA](https://aka.ms/saca) and [zero trust](https://learn.microsoft.com/security/zero-trust/) guidance
- Deployable in Azure Commercial, Azure Government, Azure Government Secret, and Azure Government Top Secret clouds
- A simple solution with low configuration and narrow scope
- Written as [Bicep](./src/) templates

Mission Landing Zone is the right solution when:

- A simple, secure, and scalable hub and spoke infrastructure is needed.
- A central IT team is administering cloud resources on behalf of other teams and workloads.
- There is a need to implement SCCA with zero trust.
- Hosting any workload requiring a secure environment, for example: data warehousing, AI/ML, and containerized applications.

Design goals include:

- A simple, minimal set of code that is easy to configure
- Good defaults that allow experimentation and testing in a single subscription
- Deployment via command line or with a user interface

Our intent is to enable IT Admins to use this software to:

- Test and evaluate the landing zone using a single Azure subscription
- Develop a known good configuration that can be used for production with multiple Azure subscriptions
- Customize the deployment configuration to suit specific needs
- Deploy multiple customer workloads in production.

## Deployment Options

Mission Landing Zone can be deployed from the Azure Portal, or with Azure command line tools. Choose the desired option below for detailed deployment documentation.

| Method | Supported Clouds |
| :----- | :--------------- |
| [Azure Portal](./docs/deployment-guides/portal.md) | Azure Commercial, Azure Government |
| [Template Spec](./docs/deployment-guides/template-spec.md) | Azure Commercial, Azure Government, Azure Government Secret, & Azure Government Top Secret |
| [Command Line Tools](./docs/deployment-guides/command-line-tools.md)  | Azure Commercial, Azure Government, Azure Government Secret, & Azure Government Top Secret |

> [!NOTE]
> Be sure to check out our **[add-ons](./src/add-ons/README.md)** to accelerate workload deployments.

## Azure Firewall Public IP Addresses

The MLZ deployment supports multiple static public IP addresses (PIPs) for Azure Firewall. Use the `additionalFwPipCount` parameter to specify the number of additional static PIPs to create for NAT rules. All PIPs are static and follow the same naming and diagnostic logging conventions. See [networking.md](docs/networking.md) for details and examples.

**Parameter:**

- `additionalFwPipCount` (int, default: 0): Number of additional static public IP addresses to create for the Azure Firewall. Set to 0 for default behavior (single PIP), or increase as needed for your NAT scenarios.

**Example:**

```bicep
param additionalFwPipCount int = 2
```

This will provision two additional static PIPs for the Azure Firewall, in addition to the default one.

## Sentinel Integration Package

The `mlz/sentinel` directory groups the Sentinel automation and content that extend the baseline Mission Landing Zone deployment. Keep Sentinel artifacts destined for MLZ in its subfolders below so they remain isolated from the upstream Mission Landing Zone source.

When you enable Microsoft Sentinel during an MLZ deployment, the platform now reuses these assets to install the Azure Activity and Microsoft Entra ID solution packages automatically. That bundle turns on the matching data connectors, publishes the curated hunting queries, analytic rules, workbooks, and deploys the pre-wired Logic App playbooks (remember to authorize their API connections after deployment).

```text
mlz/sentinel/
    infrastructure/   Bicep templates, parameters, and deployment plumbing for MLZ
    automation/       PowerShell or CLI automation that configures MLZ-integrated workspaces
    content/          Analytic rules, hunting queries, metadata, workbooks, and playbooks tailored for MLZ
    docs/             Documentation that explains how to deploy/operate the MLZ Sentinel package
    tests/            Validation assets (Pester, script tests, pipelines) specific to the MLZ buildout
```

Add new folders or files under these roots as the MLZ effort expands. The top-level Mission Landing Zone structure remains untouched so existing workflows continue without disruption.
