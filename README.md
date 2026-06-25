# JAWS

JAWS is an agentic operations platform being rebuilt from a clean open-source foundation using the Microsoft Agent Framework tutorial path as scaffolding.

The tutorial source, tests, and documentation grow release by release. The Step 1 code establishes a runnable first agent and local API validation path; later releases add tools, multi-turn conversations, memory, workflows, hosting, Teams integration, and the Datadog-to-ServiceNow operations scenario.

## Credential Model

The standalone code tutorial does not use `DefaultAzureCredential`. Local model validation uses an explicit Azure AI or Azure OpenAI endpoint key through `AzureKeyCredential`, with real local secrets kept in `appsettings.Development.local.json` or environment variables that are ignored by Git.

The installation package uses a different boundary: installation inputs provide model, Datadog, ServiceNow, and Teams credentials; secrets are stored in Azure Key Vault or Key Vault-backed application settings; Azure-hosted resource operations use explicitly configured managed identity and RBAC assignments instead of a broad default credential chain.

## Current Scope

- Clean public/open-source track
- No copied implementation code from prior private work
- No tenant-specific Azure, ServiceNow, Datadog, or Teams secrets in source control
- Code, docs, and tests are added as each Microsoft Agent Framework phase is designed, approved, implemented, and tested

## Repository Layout

- `src/Jaws.AgentFramework` contains the Agent Framework implementation.
- `src/Jaws.Api` contains the local API surface used by the tutorial.
- `tests` contains release-aligned validation tests.
- `docs/tutorial/index.html` contains the HTML tutorial.
