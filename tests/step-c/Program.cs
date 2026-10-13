using Jaws.Investigation;

var failures = new List<string>();
int passed = 0;
async Task Check(string name, Func<Task<bool>> test)
{
    try
    {
        if (await test()) { passed++; Console.WriteLine($"PASS {name}"); }
        else { failures.Add(name); Console.Error.WriteLine($"FAIL {name}"); }
    }
    catch (Exception ex) { failures.Add(name); Console.Error.WriteLine($"FAIL {name}: {ex.Message}"); }
}
var guid = Guid.NewGuid().ToString();
var scope = new VerifiedInvestigationScope(
    TenantId: Guid.NewGuid().ToString(),
    UserObjectId: Guid.NewGuid().ToString(),
    ProjectId: "dev-project",
    ConversationId: "conversation-1",
    AuthorizationContextRef: "validated-broker-context",
    TargetResourceScope: "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-test/providers/Microsoft.Compute/virtualMachines/vm-test-01",
    AllowedToolNames: ["AzurePolicy.Read", "Defender.Read"],
    DeadlineUtc: DateTimeOffset.UtcNow.AddMinutes(5),
    IsVerifiedByBroker: true);
var request = new InvestigationTask("1.0", guid, Guid.NewGuid().ToString(), "teams-message-1",
    "PlanReadOnlyAzureVmComplianceInvestigation", scope);
var planner = new InvestigationPlanner();
await Check("plan returns bound identity and no fabricated evidence", async () =>
{
    var result = await planner.InvestigateAsync(request);
    return result.Status == InvestigationStatus.Planned &&
        result.TaskId == request.TaskId && result.CorrelationId == request.CorrelationId &&
        result.Evidence.Count == 0 && result.VerifiedClaims.Count == 0 &&
        result.ProposedActions.Count == 0 && result.EvidenceRequirements.Count > 0;
});
await Check("reject unverified caller scope", async () =>
    (await planner.InvestigateAsync(request with { Scope = scope with { IsVerifiedByBroker = false } })).Status == InvestigationStatus.Denied);
await Check("reject forbidden operations", async () =>
    (await planner.InvestigateAsync(request with { RequestedOperation = "RemediateVm" })).Status == InvestigationStatus.Denied);
await Check("reject unauthorized tool", async () =>
    (await planner.InvestigateAsync(request with { Scope = scope with { AllowedToolNames = ["AzurePolicy.Write"] } })).Status == InvestigationStatus.Denied);
await Check("reject expired task", async () =>
    (await planner.InvestigateAsync(request with { Scope = scope with { DeadlineUtc = DateTimeOffset.UtcNow.AddSeconds(-1) } })).Status == InvestigationStatus.Denied);
await Check("reject unknown schema", async () =>
    (await planner.InvestigateAsync(request with { SchemaVersion = "2.0" })).Status == InvestigationStatus.Denied);
await Check("reject wildcard resource scope", async () =>
    (await planner.InvestigateAsync(request with { Scope = scope with { TargetResourceScope = "/subscriptions/*" } })).Status == InvestigationStatus.Denied);
await Check("reject incomplete tenant identity", async () =>
    (await planner.InvestigateAsync(request with { Scope = scope with { TenantId = "" } })).Status == InvestigationStatus.Denied);
await Check("reject invalid task correlation", async () =>
    (await planner.InvestigateAsync(request with { CorrelationId = "free-form" })).Status == InvestigationStatus.Denied);
await Check("reject overlong task budget", async () =>
    (await planner.InvestigateAsync(request with { Scope = scope with { DeadlineUtc = DateTimeOffset.UtcNow.AddHours(1) } })).Status == InvestigationStatus.Denied);
await Check("honor cancellation", async () =>
{
    using var cts = new CancellationTokenSource();
    cts.Cancel();
    try { await planner.InvestigateAsync(request, cts.Token); return false; }
    catch (OperationCanceledException) { return true; }
});
var delegation = new SupervisorInvestigationDelegator(planner);
await Check("Supervisor delegates a bound task and preserves correlation", async () =>
{
    var result = await delegation.DelegateAsync(request);
    return result.Status == InvestigationStatus.Planned &&
        result.TaskId == request.TaskId && result.CorrelationId == request.CorrelationId &&
        result.VerifiedClaims.Count == 0;
});
await Check("Supervisor blocks unverified tasks before specialist call", async () =>
{
    var result = await delegation.DelegateAsync(request with { Scope = scope with { IsVerifiedByBroker = false } });
    return result.Status == InvestigationStatus.Denied && result.AgentName == "jaws-supervisor";
});
await Check("Supervisor rejects a specialist that alters correlation", async () =>
{
    var fake = new StubInvestigationAgent(task =>
        new InvestigationResult("1.0",task.TaskId,Guid.NewGuid().ToString(),
            "jaws-investigation","offline",InvestigationStatus.Planned,[],[],[],[],[]));
    var result = await new SupervisorInvestigationDelegator(fake).DelegateAsync(request);
    return result.Status == InvestigationStatus.Failed && result.Diagnostics[0].StartsWith("WORKER_RESULT_REJECTED");
});
await Check("Supervisor rejects unsupported success without evidence", async () =>
{
    var fake = new StubInvestigationAgent(task =>
        new InvestigationResult("1.0",task.TaskId,task.CorrelationId,
            "jaws-investigation","offline",InvestigationStatus.Succeeded,[],[],["Claim without evidence"],[],[]));
    var result = await new SupervisorInvestigationDelegator(fake).DelegateAsync(request);
    return result.Status == InvestigationStatus.Failed;
});
Console.WriteLine($"Step C offline tests: {passed} passed; {failures.Count} failed.");
return failures.Count == 0 ? 0 : 1;

sealed class StubInvestigationAgent(Func<InvestigationTask, InvestigationResult> callback) : IInvestigationAgent
{
    public Task<InvestigationResult> InvestigateAsync(InvestigationTask task, CancellationToken cancellationToken = default)
        => Task.FromResult(callback(task));
}
