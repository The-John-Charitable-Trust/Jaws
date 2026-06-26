# Step 4 Test Cases

JAWS tutorial step: Step 4: Add Tools
Release: `0.4`

| ID | Test | Validation command or probe | Expected result |
| --- | --- | --- | --- |
| ST4-001 | Core demo tools are registered | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST4-002 | Role-agent allowed tools exist in the MCP registry | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST4-003 | Azure inventory tool returns demo resource candidates | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST4-004 | Datadog recommendation tool returns approval-gated recommendation | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST4-005 | Write-capable Datadog tool is still blocked without workflow approval | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST4-006 | Extensibility tool explains JSON job descriptions and approved MCP tools | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST4-007 | Local MCP endpoint lists the core demo tools | `POST http://localhost:5124/mcp` with `tools/list` | Tool list includes Azure, Datadog, ServiceNow, and JAWS extensibility tools |
| ST4-008 | Local MCP endpoint reports release `0.4` | `tools/call` for `jaws_mcp_status` | Returns `release=0.4`, `toolScope=tutorial-demo`, and `writeToolsEnabled=false` |
| ST4-009 | Local MCP endpoint calls read-only Azure and Datadog tools | `tools/call` for `azure.resource.inventory` and `datadog.coverage.recommend` | Returns structured provider evidence and approval-gated recommendation |
| ST4-010 | Local MCP endpoint denies write-capable execution | `tools/call` for `datadog.synthetic.create` | Returns JSON-RPC error `-32050` and `Write-capable MCP tool denied.` |
| ST4-011 | Tool descriptions expose agent-computer interface guidance | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST4-012 | JSON job description includes context, reasoning, guardrails, and tool contracts | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |

Local validation for release `0.4` is `dotnet build Jaws.slnx -c Release` plus `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj`. To validate the live tool path, run `src/Jaws.Api` locally with the `http` launch profile and confirm the objective Step 4 tutorial result: `ToolListPass=True`, `StatusPass=True`, `AzureToolPass=True`, `DatadogToolPass=True`, `WriteGatePass=True`, and `ExtensibilityPass=True`.

Step 4 also documents the tool contract as an agent-computer interface: each tool must have a clear purpose, provider boundary, parameter schema, read/write classification, and evidence result shape. Step 4 intentionally keeps provider writes disabled. Datadog synthetic creation, Datadog webhook testing, and ServiceNow incident creation are registered as write-capable tools so the final scenario has stable tool names, but execution remains blocked until a later workflow approval step enables controlled writes.
