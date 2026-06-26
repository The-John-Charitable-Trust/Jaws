# JAWS

JAWS is an agentic operations platform being rebuilt from a clean open-source foundation using the Microsoft Agent Framework tutorial path as scaffolding.

The tutorial source, tests, and documentation grow release by release. Releases `v0.1` through `v0.5` establish the first agent, MCP boundary, MCP hardening, demo tools, and multi-turn conversation support. Later releases add memory, workflows, hosting, Teams integration, and the Datadog-to-ServiceNow operations scenario.

## Credential Model

The standalone code tutorial does not use `DefaultAzureCredential`. Local model validation uses an explicit Azure AI or Azure OpenAI endpoint key through `AzureKeyCredential`, with real local secrets kept in `appsettings.Development.local.json` or environment variables that are ignored by Git.

Hosted deployment guidance is intentionally separate from the code tutorial and will be documented with the release `1.0` deployment path. The code tutorial uses local configuration and an explicit endpoint API key for model validation; the future hosted path will protect secrets in Azure Key Vault or Key Vault-backed application settings and use managed identity with RBAC for Azure-hosted resource operations where appropriate.

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
