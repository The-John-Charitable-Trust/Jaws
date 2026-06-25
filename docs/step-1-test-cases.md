# Step 1 Test Cases

Release: `0.1`
Microsoft documentation step: Step 1: Your First Agent

| ID | Test | Method | Expected Result |
|---|---|---|---|
| ST1-001 | First agent options validate required fields | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST1-002 | Naming policy generates governed Azure names | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST1-003 | Role agent catalog includes support, governance, deploy, and workflow agents | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST1-004 | Deploy agent requires approval and evidence settings | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST1-005 | Solution builds | `dotnet build Jaws.slnx -c Release` | PASS |
| ST1-006 | Local API health endpoint reports configuration state | `GET http://localhost:5124/health` | Returns `status=healthy`, `release=0.1`, and no configuration errors |
| ST1-007 | Local first agent executes against configured model | `POST http://localhost:5124/api/agent/run` | Returns a non-empty model answer with `agentName=JawsFirstAgent` and `release=0.1` |

Local validation for release `0.1` is `dotnet build Jaws.slnx -c Release` plus `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj`. To validate the live model path, run `src/Jaws.Api` locally with the `http` launch profile and confirm the objective Step 1 tutorial result: `HealthPass=True` and `AgentPass=True`.

The natural-language model answer is intentionally not deterministic. Step 1 passes when the configuration, health endpoint, first-agent construction, model call, and response metadata pass the documented checks.

