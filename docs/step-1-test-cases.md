# Step 1 Test Cases

Release: `0.1`
Microsoft documentation step: Step 1: Your First Agent

| ID | Test | Method | Expected Result |
|---|---|---|---|
| ST1-001 | First agent options validate required fields | `dotnet run --project tests/Jaws.FirstAgent.Tests` | PASS |
| ST1-002 | Naming policy generates governed Azure names | `dotnet run --project tests/Jaws.FirstAgent.Tests` | PASS |
| ST1-003 | Solution builds | `dotnet build Jaws.slnx` | PASS |
| ST1-004 | API health endpoint reports configuration state | `GET /health` | Returns `healthy` or actionable configuration errors |
| ST1-005 | First agent executes against configured model | `POST /api/agent/run` | Returns model answer with agent name and release metadata |

Live tests require an Azure login, reachable project endpoint, and model deployment.

