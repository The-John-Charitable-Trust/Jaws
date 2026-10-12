# JAWS Stage B1 — Security and Authorization Specification
Status: PROPOSED FOR REVIEW | Security acceptance before deployment

## 1. Non-negotiable invariants
SEC-001 Every Azure deployment, configuration, RBAC assignment, endpoint change, upgrade and repair MUST occur through the JAWS installer; no tutorial or support runbook should require manual cloud modifications.
SEC-002 A worker may not exercise privileges beyond the initiating user's effective authorization AND the operation's JAWS policy allowance. A workload managed identity may authenticate platform components but may not silently expand user authority.
SEC-003 Every consequential write requires policy authorization and human-in-the-loop approval bound to exact action, target, scope, preview hash, user, expiry and one-time execution ID.
SEC-004 Tool output, retrieved documents, model text and inter-agent messages are untrusted input. Never allow prompt injection to change privileges, approved tool lists or tenant scope.
SEC-005 Multi-tenant and project data must never cross tenant/project security boundaries. Restrict logs/evidence to authorized viewers.
SEC-006 Read-only operation must have no cloud mutations, including hidden role assignments or silent resource provisioning.
SEC-007 Installer fails closed on unknown ownership, authorization, incomplete tenant inventory, identity drift or unvalidated endpoint identity.

## 2. Identity and authorization
1. Validate inbound Teams/Microsoft identity via supported signed tokens, issuer/audience/tenant, replay controls and conversation membership, NOT a caller-supplied user ID.
2. Bind tenantId, userObjectId, Teams conversation and JAWS project to a server-owned authorization context; never trust fields supplied by the LLM or worker.
3. For Azure, prefer genuine delegated user tokens where the downstream interface supports them; validate actual effective scope/permissions at execution. Where delegation is unsupported, the authorization broker must verify user permission independently, apply narrower service policies, and clearly mark service-principal execution. Deny when equivalence cannot be established.
4. For Datadog, Azure RBAC is irrelevant to Datadog roles; implement separately verified Datadog identity/role and resource permissions. A single broad Datadog integration token must not grant all Teams users its full authority.
5. Use managed identities for platform-to-platform connections and scoped access to secrets, segregated per worker/provider. Rotate secrets and avoid logging credentials.
6. Separate installer operator privileges from runtime worker privileges, and read-only investigation from approved write/remediation roles.

## 3. Trust boundaries
- Teams ingress: verify sender and tenant, anti-replay, rate limits, allowed channels, membership.
- Supervisor -> worker: mutual service authentication, narrow audience, signed/broker-derived authorization context, typed schema validation, task budget and correlation IDs.
- Worker -> MCP: explicitly allow-listed tools, strict parameter JSON schemas, resource scope filters, deny arbitrary provider endpoints.
- Worker -> code sandbox: isolated per worker/task, bounded CPU/memory/runtime/network, no elevated host privilege, no host Docker socket, no host filesystem mounting.
- Sandbox -> provider: no ambient owner/contributor token; mint task-scoped credentials after authorization only.
- Evidence store: provenance, immutable audit trail for approvals and execution, redacted output, retention policy, authorized retrieval.

## 4. Action classification
| Category | Examples | Required gates |
|---|---|---|
| Read | VM configuration, Azure Policy status, Datadog metrics | Verified user authorization + tool allowlist + project isolation |
| Analysis | Python data aggregation and report creation | Read authorization + isolated sandbox + network/compute limits |
| Proposed change | Remediation script/monitor changes | Evidence, linting, impact/what-if, no execution |
| Write | VM mutation, monitor creation, RBAC-sensitive changes | Exact approved action + recheck authorization + one-time audit receipt |
| Privilege changes | RBAC changes/new credentials | Installer-only for setup; strong operator review, cannot be worker-initiated bypass |

## 5. Audit events
Emit machine-readable events: identity validation, project selection, task delegated, policy decision, tool call begin/end, sandbox start/end, evidence reference, approval requested/decided/expired, provider write attempted/completed, installer plan/applied/validated. Include UTC time, correlation ID, tenant, project, user, worker, operation, normalized scope and result. Never store bearer tokens or secrets.

## 6. Minimum negative cases
- Forged userId/projectId/tenantId and invalid Teams token; deny.
- Read-only user tries Azure write; deny even if worker managed identity can write.
- Datadog user without Datadog permission; deny even if integration token has access.
- Cross-project or cross-tenant session/memory retrieval; deny.
- Prompt injection asks to call undeclared MCP tool, ignores instruction.
- Worker task changes requested scope; deny.
- Approval replay, expired approval, changed script hash; deny.
- Network egress to unapproved endpoint, credential exfiltration, arbitrary shell privilege escalation; deny.
- Timeout/cost quota reached; terminate task and record evidence.

## 7. Controls requiring implementation and validation
Identity delegation/OBO, Conditional Access considerations, Foundry hosting isolation, Container Apps sessions availability, Datadog scopes, safe PowerShell/Python runner, security event storage, Teams admin deployment model and permission evaluation need implementation-specific proofs. B1 specifies requirements only. Do not mark these compliant before validated tests.
