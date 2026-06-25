# Step 1 Test Cases

Release: `0.1`
Microsoft documentation step: Step 1: Your First Agent

| ID | Test | Method | Expected Result |
|---|---|---|---|
| ST1-001 | First agent options validate required fields | `dotnet run --project tests/Jaws.FirstAgent.Tests` | PASS |
| ST1-002 | Naming policy generates governed Azure names | `dotnet run --project tests/Jaws.FirstAgent.Tests` | PASS |
| ST1-003 | Role agent catalog includes support, governance, deploy, and workflow agents | `dotnet run --project tests/Jaws.FirstAgent.Tests` | PASS |
| ST1-004 | Deploy agent requires approval and evidence settings | `dotnet run --project tests/Jaws.FirstAgent.Tests` | PASS |
| ST1-005 | Solution builds | `dotnet build Jaws.slnx` | PASS |
| ST1-006 | Optional hosted API health endpoint reports configuration state | `GET /health` against a deployed API | Returns `healthy` or actionable configuration errors |
| ST1-007 | Optional hosted first agent executes against configured model | `POST /api/agent/run` against a deployed API | Returns model answer with agent name and release metadata |

Local validation for release `0.1` is `dotnet build Jaws.slnx` plus `dotnet run --project tests/Jaws.FirstAgent.Tests`. Hosted API validation is optional at this point because the Step 1 code tutorial does not provision Azure App Service. Hosted validation requires a deployed API, configured runtime settings, Azure login or managed identity, a reachable Azure AI endpoint, and a model deployment.

