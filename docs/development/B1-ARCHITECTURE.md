# JAWS Stage B1 — Multi-Agent Architecture Specification
Status: PROPOSED FOR REVIEW | No Azure changes | Baseline: Stage A Discover v0.4.6

> **Superseded for planning by the installation roadmap and `SpecialistCatalog`.** The Supervisor is the Teams proxy. One specialist is one agent and performs investigation, deliberation, and remediation for its own job. The virtual-machine specialist owns the one compute environment and uses Azure MCP. The observability specialist uses that environment through a custom MCP server whose tools are Datadog, Azure Monitor, Azure Sentinel, and ServiceNow incident records. Azure network, Azure storage, and ServiceNow change fulfillment are later one-agent specializations. See `docs/installation/IMPLEMENTATION_ROADMAP.md`. The sections below are the earlier review draft.

## 1. Scope and evidence
This is the target design, not proof of deployed components. The repository contains a local C#/.NET 10 Agent Framework tutorial agent, role-agent factory, demo MCP registry, local conversations, and an accepted read-only Stage A installer. Production Foundry hosted agents, worker sandboxes, Teams adapter, real Azure MCP integration, real Datadog MCP integration and durable conversation storage are NOT yet implemented or accepted. Preserve the original `docs/tutorial/index.html` unchanged.

## 2. Logical architecture
```text
Microsoft Teams (personal / team / channel conversation)
   | authenticated request + tenant/user/project/conversation identity
   v
JAWS Teams adapter / ingress (validates token, policy, correlation)
   v
JAWS Supervisor Agent — Microsoft Foundry hosted agent (target)
   |-- session / project / authorization broker / audit / human approval
   |-- delegated task with bound scope and correlation ID
   +--> Azure VM Security & Compliance Worker — isolated hosted agent (target)
   |       |--> official Azure MCP Server, only supported tools
   |       +--> dedicated isolated execution sandbox for approved Python/PowerShell tasks
   |       +--> Azure Policy / Defender for Cloud / Resource Graph / VM data
   +--> Datadog Observability Worker — isolated hosted agent (target)
           |--> custom Datadog MCP Server, approved tools
           +--> separate isolated execution sandbox
           +--> Datadog metrics / logs / traces / monitors
   |
   v
Supervisor validates typed worker outputs, evidence, permission decisions,
approval receipts; returns project-scoped response to originating Teams conversation.
```

## 3. Component responsibilities
| Component | Owns | Does not own |
|---|---|---|
| Teams adapter | Verified Teams/Entra context, message/thread identity, rate limiting, response routing | Agent business reasoning or infrastructure provisioning |
| Supervisor | Intent, delegation, orchestration, evidence synthesis, approval initiation, conversation identity | Direct privileged Azure/Datadog commands or unrestricted shell |
| Azure specialist | VM inventory, posture, control mapping, findings with citations | Privilege elevation, arbitrary Azure writes |
| Datadog specialist | Monitoring analyses, telemetry evidence, operational diagnosis | Unapproved monitor/webhook mutation or shared Azure authority |
| Authorization/approval broker | Effective user scope, service entitlements, allow/deny decision, immutable approvals, audit | Granting user new privileges |
| MCP adapters | Typed tool contracts, narrow provider interfaces, validated evidence | Deciding user authority independently |
| Execution sandboxes | Bounded short-lived scripts with restricted egress, CPU/memory/time, input/output controls | Persistent unbounded credentials or unrestricted subscription access |
| Installer | All Azure creation/reuse/configuration/RBAC/deployment/repair/validation | Skipping operator approval or altering unrelated infrastructure |

## 4. Runtime and communication design
- Use Microsoft Agent Framework C#/.NET 10 as the orchestration implementation baseline, retain existing AgentJobDescription and RoleAgentFactory where appropriate.
- Supervisor and each worker have distinct agent identities, instructions, tools, logs, versioning and deployment lifecycles.
- Typed requests include: schemaVersion, taskId, correlationId, tenantId, userObjectId, projectId, conversationId, originatingTeamsMessageId, requestedOperation, targetResourceScope, authorizationContextRef, requiredApproval, deadlineUtc, and allowedToolNames.
- Typed responses include: taskId, agentName/version, status (Succeeded/Partial/Denied/Failed), evidence[] with provider links, claims[], actionsProposed[], diagnostics[] and correlationId. Do not treat model-produced citations as authoritative without evidence validation.
- Enforce bounded delegation depth, per-tool timeouts, retries with idempotency keys and circuit breaking. Workers must not invoke one another directly without Supervisor policy.
- Supervisory project/session context is separate from Teams channel/thread metadata. Tenant + project + authorized principal partition retrieval and persistence.
- Keep ServiceNow and remediation integrations as future optional additions, not prerequisites of this B1 two-worker MVP.

## 5. Execution environment decision record — B1 provisional
Preferred target is separate worker-bound Azure Container Apps execution environments or sessions for Python/PowerShell while agent reasoning is hosted in Microsoft Foundry. Evaluate Foundry built-in sandboxes against Container Apps sessions before selecting SKUs and implementation. Ensure no shared writable filesystem or secret store between workers; per-task ephemeral execution preferred. Host boundaries do not establish downstream user authorization automatically. Cost/quotas/idle resource charges must be evaluated in Installer Plan.

## 6. Teams project and conversation model
JAWS Project is a logical entity under a tenant and access policy; it is NOT assumed to equal a Teams team or channel. Map conversationId to (tenantId, projectId, Teams conversationId, Teams thread/root messageId, user membership). Personal chat chooses active project explicitly; channel-scoped conversations may have a policy-controlled project default. No cross-project memory retrieval, even if a user can access both; share by explicit authorized action only.

## 7. External dependencies and deployment boundaries
The installer configures Azure-side resources, identities, hosted services, endpoints, network controls and Teams app package settings. Tenant-side Teams/Microsoft 365 app approval may still require an authorized administrator's consent; installer should present the approval requirement and verify its status, not impersonate the administrator. Datadog organization provisioning/API permissions similarly require authorized integration setup; secrets must remain outside Git. Workload identities must not be used as a substitute for the initiating user's effective authorization.

## 8. Baseline and migration
Stage A is frozen as the accepted read-only Discover behavior. Preserve its authoritative state and resource ownership model; extend schema/version only through explicit migrations, without silently overwriting the existing development state file. Do not adopt legacy Tight Fang resources. B1 approves architecture only; B2 develops installation automation.

## 9. Open decisions for approval
1. Foundry hosting capability/region/plan support and implementation API version.
2. Container Apps sessions versus other per-worker sandbox substrate; per-task versus per-project lifetime.
3. Delegated Azure identity/On-Behalf-Of flows versus a broker enforcing verified user RBAC and explicit narrower service policy for operations unsupported by delegated tokens.
4. Datadog user-to-role/credential mapping and minimum API scopes; fail closed when unavailable.
5. Data persistence, encryption, retention and Teams project mapping.
6. Tenant-specific Teams app distribution/approval route.
7. B3 live testing budget, SKU and spending approval.
