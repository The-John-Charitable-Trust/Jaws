# Installer-managed publishing of a previously built JAWS Supervisor Docker image.
# Plan is local-only. Publish requires exact digest approval and authenticates to ACR.
Set-StrictMode -Version Latest
function Get-JawsSupervisorPublishPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$RegistryReceipt,
        [Parameter(Mandatory)][string]$LocalImageId
    )
    if ($State.Platform -ne 'JAWS' -or $RegistryReceipt.Status -ne 'CREATED_AND_VERIFIED' -or
        $RegistryReceipt.Ownership -ne 'InstallerCreated' -or $RegistryReceipt.CreatedByInstaller -ne $true -or
        $RegistryReceipt.AdminEnabled -ne $false -or $RegistryReceipt.Sku -ne 'Basic') {
        throw 'JAWS-PUSH-001: Verified installer-owned registry receipt required.'
    }
    if ($LocalImageId -notmatch '^sha256:([a-fA-F0-9]{64})$') {
        throw 'JAWS-PUSH-002: A local image ID with sha256 digest is required.'
    }
    $registry=[string]$RegistryReceipt.LoginServer
    if ($registry -cnotmatch '^([a-z0-9]{5,50})\.azurecr\.io$') {
        throw 'JAWS-PUSH-003: Invalid registry server.'
    }
    $name=$Matches[1]
    $expected="/subscriptions/$($State.SubscriptionId)/resourceGroups/$($State.ResourceGroupName)/providers/Microsoft.ContainerRegistry/registries/$name"
    if ([string]$RegistryReceipt.RegistryResourceId -ine $expected) {
        throw 'JAWS-PUSH-004: Registry receipt does not match authoritative state scope.'
    }
    $tag='build-' + $LocalImageId.Substring(7,16).ToLowerInvariant()
    $payload=[ordered]@{
        Version='1.0';Action='PublishSupervisorContainer';SubscriptionId=[string]$State.SubscriptionId
        ResourceGroupName=[string]$State.ResourceGroupName;RegistryName=$name
        RegistryResourceId=$expected;Repository='jaws/supervisor'
        SourceImage='jaws-supervisor:local';SourceImageId=$LocalImageId.ToLowerInvariant()
        TargetTag="$registry/jaws/supervisor:$tag";Platform='linux/amd64'
    }
    $json=ConvertTo-Json -InputObject $payload -Depth 10 -Compress
    $hash=[System.Security.Cryptography.SHA256]::Create()
    try {$bytes=$hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))}
    finally {$hash.Dispose()}
    [pscustomobject]@{
        PlanSha256=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
        Status='BLOCKED_PENDING_PUSH_APPROVAL_AND_DATA_PLANE_RBAC'
        Plan=$payload
        CanPublishWithoutApproval=$false;AzureWrites=0
        Cost='Registry already billable; image storage/network transfer charges may apply. Exact charges unverified.'
    }
}
function Invoke-JawsSupervisorPublish {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)
    if ($Plan.Plan.Action -ne 'PublishSupervisorContainer' -or
        $Plan.Plan.TargetTag -notmatch '^([a-z0-9]{5,50})\.azurecr\.io/jaws/supervisor:build-[a-f0-9]{16}$' -or
        $Plan.Plan.SourceImage -ne 'jaws-supervisor:local' -or
        $Plan.Plan.SourceImageId -notmatch '^sha256:[a-f0-9]{64}$') {
        throw 'JAWS-PUSH-005: Invalid publish plan.'
    }
    $serialized=ConvertTo-Json -InputObject $Plan.Plan -Depth 10 -Compress
    $hasher=[System.Security.Cryptography.SHA256]::Create()
    try { $actualBytes=$hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($serialized)) }
    finally { $hasher.Dispose() }
    $actualHash=([BitConverter]::ToString($actualBytes)).Replace('-','').ToLowerInvariant()
    if ($actualHash -cne $Plan.PlanSha256) {
        throw 'JAWS-PUSH-022: Deployment payload changed after fingerprint generation.'
    }
    $sub=[string]$Plan.Plan.SubscriptionId; $rg=[string]$Plan.Plan.ResourceGroupName
    $registry=[string]$Plan.Plan.RegistryName
    $account=& az account list --all --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or -not @((($account | Out-String | ConvertFrom-Json) | Where-Object { $_.id -ieq $sub -and $_.state -eq 'Enabled' })).Count) {
        throw 'JAWS-PUSH-006: Target Azure subscription not visible.'
    }
    $observedJson=& az acr show --name $registry --resource-group $rg --subscription $sub --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-PUSH-007: Registry not readable.'}
    $obs=$observedJson | Out-String | ConvertFrom-Json
    if ([string]$obs.id -ine [string]$Plan.Plan.RegistryResourceId -or
        [string]$obs.loginServer -ine "$registry.azurecr.io" -or
        $obs.adminUserEnabled -ne $false -or [string]$obs.sku.name -ne 'Basic' -or
        [string]$obs.tags.application -ine 'JAWS' -or
        [string]$obs.tags.managedBy -ine 'JAWS-Installer') {
        throw 'JAWS-PUSH-008: Registry identity, ownership tags or security drift.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {throw 'JAWS-PUSH-009: Docker unavailable.'}
    $actualId=(& docker image inspect $Plan.Plan.SourceImage --format '{{.Id}}' 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualId -ine [string]$Plan.Plan.SourceImageId) {
        throw 'JAWS-PUSH-010: Local Docker image changed since approval.'
    }
    # Avoid overwriting an already published tag. Query failure is treated as inconclusive.
    $repoListJson=& az acr repository list --name $registry --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'JAWS-PUSH-020: Repository listing failed; cannot prove image tag is unused.'
    }
    $repoList=@($repoListJson | Out-String | ConvertFrom-Json)
    if ($repoList -contains 'jaws/supervisor') {
        $tags=& az acr repository show-tags --name $registry --repository 'jaws/supervisor' --output json --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw 'JAWS-PUSH-021: Existing repository tags not readable.'
        }
        $allTags=@($tags | Out-String | ConvertFrom-Json)
        if ($allTags -contains ($Plan.Plan.TargetTag -split ':')[-1]) {
            throw 'JAWS-PUSH-011: Target image tag already exists; refuse overwrite.'
        }
    }
    # Authenticate using Entra credentials; do not enable the registry admin account.
    & az acr login --name $registry --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-PUSH-012: ACR data-plane authentication failed; check AcrPush/Repository Writer.'}
    & docker tag $Plan.Plan.SourceImage $Plan.Plan.TargetTag
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-PUSH-013: Docker tag failed.'}
    # Docker emits progress on stdout. Display it without adding strings to the function's return objects.
    & docker push $Plan.Plan.TargetTag | Out-Host
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-PUSH-014: Docker push failed; inspect partial registry state before retry.'}
    $metadata=& az acr manifest show-metadata --registry $registry --name "jaws/supervisor:$((($Plan.Plan.TargetTag) -split ':')[-1])" --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-PUSH-015: Registry digest verification unavailable; do not deploy.'}
    $manifest=$metadata | Out-String | ConvertFrom-Json
    $digest=[string]$manifest.digest
    if ($digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
        throw 'JAWS-PUSH-016: Registry did not return a valid immutable digest.'
    }
    [pscustomobject]@{
        Status='PUBLISHED_AND_DIGEST_VERIFIED';Repository='jaws/supervisor'
        Image="$registry.azurecr.io/jaws/supervisor@$digest";RegistryManifestDigest=$digest
        PlanSha256=$Plan.PlanSha256;FoundryDeploymentPerformed=$false
        RegistryPushPerformed=$true
    }
}
Export-ModuleMember -Function Get-JawsSupervisorPublishPlan,Invoke-JawsSupervisorPublish
