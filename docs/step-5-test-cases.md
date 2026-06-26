# Step 5 Test Cases

JAWS tutorial step: Step 5: Multi-Turn Conversations
Release: `0.5`

| ID | Test | Validation command or probe | Expected result |
| --- | --- | --- | --- |
| ST5-001 | Conversation store creates conversation IDs | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST5-002 | Conversation store increments turns for the same conversation | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST5-003 | Conversation reset starts a fresh local turn state | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST5-004 | Agent response exposes conversation metadata | `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj` | PASS |
| ST5-005 | Local API first turn creates a conversation ID | `POST http://localhost:5124/api/agent/run` without `conversationId` | Returns `conversationRelease=0.5`, `turnNumber=1`, and non-empty `conversationId` |
| ST5-006 | Local API second turn reuses the conversation ID | `POST http://localhost:5124/api/agent/run` with prior `conversationId` | Returns the same `conversationId` and `turnNumber=2` |
| ST5-007 | Local API reset endpoint resets local turn state | `POST http://localhost:5124/api/conversations/reset` | Returns `conversationReset=true` and `turnNumber=0` |

Local validation for release `0.5` is `dotnet build Jaws.slnx -c Release` plus `dotnet run --project tests/Jaws.FirstAgent.Tests/Jaws.FirstAgent.Tests.csproj`. To validate the live model path, run `src/Jaws.Api` locally with the `http` launch profile and confirm the objective Step 5 tutorial result: `FirstTurnPass=True`, `SecondTurnPass=True`, `AnswerPass=True`, and `ResetPass=True`.

Step 5 intentionally uses in-memory conversation state. The state is lost when the local API process stops. Durable memory, RAG, storage providers, and Teams conversation mapping are introduced in later tutorial releases.
