# Step 2 Test Cases

Release: `0.2`
JAWS tutorial step: Step 2: Add MCP Server

| ID | Test | Method | Expected Result |
|---|---|---|---|
| ST2-001 | MCP registry exposes Step 2 read-only tools | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST2-002 | MCP server initializes | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST2-003 | MCP server lists tools | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST2-004 | MCP server calls the status tool | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST2-005 | MCP server rejects unknown tools | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST2-006 | Solution builds | `dotnet build Jaws.slnx -c Release` | PASS |
| ST2-007 | Local MCP endpoint lists registered tools | `POST http://localhost:5124/mcp` with `tools/list` | Returns JSON-RPC `2.0` and two registered tools |
| ST2-008 | Local MCP endpoint calls status tool | `POST http://localhost:5124/mcp` with `tools/call` for `jaws_mcp_status` | Returns `status=ok`, `server=jaws-custom-mcp`, `release=0.2`, and `writeToolsEnabled=false` |

Local validation for release `0.2` is `dotnet build Jaws.slnx -c Release` plus `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj`. To validate the live MCP path, run `src/Jaws.Api` locally with the `http` launch profile and confirm the objective Step 2 tutorial result: `ListPass=True`, `StatusPass=True`, and `WriteToolsDisabled=True`.

Step 2 intentionally exposes only read-only MCP tools. Authentication, authorization, request limits, audit hardening, and write-tool approval checks are introduced in Step 3.
