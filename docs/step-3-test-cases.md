# Step 3 Test Cases

Release: `0.3`
JAWS tutorial step: Step 3: Secure MCP Server

| ID | Test | Method | Expected Result |
|---|---|---|---|
| ST3-001 | MCP server rejects invalid JSON-RPC version | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST3-002 | MCP server returns safe unsupported method errors | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST3-003 | MCP server rejects undeclared tool arguments | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST3-004 | MCP tool metadata declares read-only annotations | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST3-005 | MCP server rejects unknown tools without echoing caller-supplied tool names | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST3-006 | Solution builds | `dotnet build Jaws.slnx -c Release` | PASS |
| ST3-007 | Local MCP endpoint rejects unsupported methods safely | `POST http://localhost:5124/mcp` with an unsupported method | Returns JSON-RPC error `-32601`, safe message, and correlation ID |
| ST3-008 | Local MCP endpoint rejects undeclared arguments | `POST http://localhost:5124/mcp` with extra arguments for `jaws_mcp_status` | Returns JSON-RPC error `-32602` and `Tool arguments failed validation.` |
| ST3-009 | Local MCP status reports hardened local mode | `POST http://localhost:5124/mcp` with `tools/call` for `jaws_mcp_status` | Returns `release=0.3`, `securityMode=hardened-local`, and `writeToolsEnabled=false` |

Local validation for release `0.3` is `dotnet build Jaws.slnx -c Release` plus `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj`. To validate the live MCP path, run `src/Jaws.Api` locally with the `http` launch profile and confirm the objective Step 3 tutorial result: `SafeMethodError=True`, `SchemaValidation=True`, `StatusHardened=True`, and `ReadOnlyAnnotations=True`.

Do not use the Step 2 `StatusPass` assertion for Step 3. Step 2 checks for `release=0.2`; Step 3 correctly reports `release=0.3` and should be validated with `StatusHardened=True`.

Step 3 implements the first security hardening slice for the custom MCP server. The security posture is based on [Model Context Protocol (MCP) Security](https://github.com/cosai-oasis/ws4-secure-design-agentic-systems/blob/main/model-context-protocol-security.md), published by CoSAI Workstream 4: Secure Design Patterns for Agentic Systems. The local tests cover the first application-level controls: explicit tool boundaries, read/write separation, input validation, safe errors, human-approval gating for write-capable tools, and audit-friendly correlation.
