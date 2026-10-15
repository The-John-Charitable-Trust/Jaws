BeforeAll {
 Import-Module (Join-Path $PSScriptRoot '../../installer/modules/FoundrySupervisorReconciliation.psm1') -Force
 $script:url='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
 $script:image='jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:'+('a'*64)
 $script:candidate=[pscustomobject]@{
  version='draft-100';status='active';draft=$true
  definition=[pscustomobject]@{
   container_configuration=[pscustomobject]@{image=$script:image}
   environment_variables=[pscustomobject]@{JAWS_INVESTIGATION_TOOLBOX_NAME='jaws-investigation-a2a-tools'}
  }
 }
}
Describe 'Foundry Supervisor candidate lifecycle' {
 It 'reconciles one active draft by immutable image and toolbox' {
  $v=Resolve-JawsSupervisorCandidate -Versions @($script:candidate) -Image $script:image
  $v.Version | Should -Be 'draft-100'
 }
 It 'refuses ambiguous matching images' {
  {Resolve-JawsSupervisorCandidate -Versions @($script:candidate,$script:candidate) -Image $script:image} | Should -Throw '*Ambiguous*'
 }
 It 'requires complete pagination and follows the returned continuation' {
  $start="$($script:url)/agents/jaws-supervisor-dev/versions?api-version=v1&include_drafts=true"
  $next="$($script:url)/agents/jaws-supervisor-dev/versions?api-version=v1&continuation=abc"
  $continued="$($script:url)/agents/jaws-supervisor-dev/versions?api-version=v1&continuation=abc&include_drafts=true"
  $candidate=$script:candidate
  $seen=[System.Collections.Generic.List[string]]::new()
  $fetch={param($url) $seen.Add($url); if($url -eq $start){return [pscustomobject]@{data=@();nextLink=$next}};return [pscustomobject]@{data=@($candidate);has_more=$false}}.GetNewClosure()
  $all=@(Get-JawsSupervisorVersionInventory -ReadPage $fetch -ProjectEndpoint $script:url)
  $all.Count | Should -Be 1
  $detail="$($script:url)/agents/jaws-supervisor-dev/versions/draft-100?api-version=v1"
  $seen | Should -Be @($start,$continued,$detail)
 }
 It 'hydrates version-list summaries from version detail' {
  $fetch={
    param($url)
    if($url -match '/versions/draft-100\\?'){
      return $script:candidate
    }
    return [pscustomobject]@{data=@([pscustomobject]@{version='draft-100';status='active';draft=$true})}
  }
  $all=@(Get-JawsSupervisorVersionInventory -ReadPage $fetch -ProjectEndpoint $script:url)
  $all.Count | Should -Be 1
  $all[0].definition.container_configuration.image | Should -Be $script:image
 }
 It 'rejects malformed version identifiers before requesting version details' {
  $fetch={param($url) [pscustomobject]@{data=@([pscustomobject]@{version='../other'})}}
  {Get-JawsSupervisorVersionInventory -ReadPage $fetch -ProjectEndpoint $script:url} | Should -Throw '*Invalid version identifier*'
 }
 It 'rejects unsafe pagination host changes' {
  $fetch={param($u) [pscustomobject]@{data=@();nextLink='https://other.example/agent'}} 
  {Get-JawsSupervisorVersionInventory -ReadPage $fetch -ProjectEndpoint $script:url} | Should -Throw '*Unexpected continuation*'
 }
 It 'tolerates transient absent drafts without writing' {
  $counter=[pscustomobject]@{Value=0}
  $candidate=$script:candidate
  $fetch={param($url) $counter.Value++; if($counter.Value -eq 1){return [pscustomobject]@{data=@()}};return [pscustomobject]@{data=@($candidate)}}.GetNewClosure()
  $result=Wait-JawsSupervisorCandidate -ReadPage $fetch -ProjectEndpoint $script:url -Image $script:image -MaxAttempts 3 -DelaySeconds 0 -Sleep {param($seconds)}
  $result.Status | Should -Be 'ACTIVE_VERIFIED'
  $result.Attempts | Should -Be 2
 }
 It 'blocks release on a terminal failure' {
  $broken=($script:candidate|ConvertTo-Json -Depth 10|ConvertFrom-Json)
  $broken.status='failed'
  $fetch={param($url) [pscustomobject]@{data=@($broken)}}.GetNewClosure()
  (Wait-JawsSupervisorCandidate -ReadPage $fetch -ProjectEndpoint $script:url -Image $script:image -MaxAttempts 1).Status | Should -Be 'FAILED'
 }
 It 'times out without creating a deployment' {
  $fetch={param($url) [pscustomobject]@{data=@()}}
  (Wait-JawsSupervisorCandidate -ReadPage $fetch -ProjectEndpoint $script:url -Image $script:image -MaxAttempts 2 -DelaySeconds 0 -Sleep {param($seconds)}).Status | Should -Be 'INDETERMINATE'
 }
 It 'retries a transient version-list 404 without deployment writes' {
  $attempt=[pscustomobject]@{Value=0}
  $candidate=$script:candidate
  $fetch={
   param($url)
   $attempt.Value++
   if($attempt.Value -eq 1){throw 'HTTP 404: Not Found'}
   [pscustomobject]@{data=@($candidate)}
  }.GetNewClosure()
  $result=Wait-JawsSupervisorCandidate -ReadPage $fetch -ProjectEndpoint $script:url -Image $script:image -MaxAttempts 2 -DelaySeconds 0 -Sleep {param($seconds)}
  $result.Status | Should -Be 'ACTIVE_VERIFIED'
  $result.Attempts | Should -Be 2
 }
 It 'fails closed on a version listing without data or value properties' {
  $fetch={param($url) [pscustomobject]@{items=@()}}
  {Get-JawsSupervisorVersionInventory -ReadPage $fetch -ProjectEndpoint $script:url} | Should -Throw '*Unrecognized version-list response*'
 }
 It 'checks installer source for state-first reconciliation before deployment release' {
  $deploy=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/FoundrySupervisorDeployment.psm1') -Raw
  $release=Get-Content (Join-Path $PSScriptRoot '../../installer/Release-JawsSupervisorCandidate.ps1') -Raw
  $deploy | Should -Match 'Get-JawsSupervisorVersionInventory'
  $release | Should -Match 'Get-JawsSupervisorVersionInventory'
  $release | Should -Match 'JAWS-SUP-CANDIDATE-012'
 }
 It 'does not accept an active draft that disappears on the next read' {
  $reads=[pscustomobject]@{Value=0}
  $candidate=$script:candidate
  $fetch={
   param($url)
   if($url -match '/versions/draft-100\?'){return $candidate}
   $reads.Value++
   if($reads.Value -eq 2){return [pscustomobject]@{data=@()}}
   return [pscustomobject]@{data=@($candidate)}
  }.GetNewClosure()
  $result=Wait-JawsSupervisorCandidate -ReadPage $fetch -ProjectEndpoint $script:url -Image $script:image -MaxAttempts 6 -DelaySeconds 0 -StableReads 3 -Sleep {param($seconds)}
  $result.Status | Should -Be 'ACTIVE_VERIFIED'
  $result.Attempts | Should -Be 5
 }
 It 'uses version detail when a list row still says active' {
  $listed=($script:candidate|ConvertTo-Json -Depth 10|ConvertFrom-Json)
  $listed.status='active'
  $failed=($script:candidate|ConvertTo-Json -Depth 10|ConvertFrom-Json)
  $failed.status='failed'
  $fetch={
   param($url)
   if($url -match '/versions/draft-100\?'){return $failed}
   return [pscustomobject]@{data=@($listed)}
  }.GetNewClosure()
  $all=@(Get-JawsSupervisorVersionInventory -ReadPage $fetch -ProjectEndpoint $script:url)
  $all[0].status | Should -Be 'failed'
 }
 It 'keeps Wait-JawsSupervisorCandidate visible after the reconcile script imports' {
  $path=Join-Path $PSScriptRoot '../../installer/Reconcile-JawsSupervisorCandidate.ps1'
  $tokens=$null;$errors=$null
  $ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path),[ref]$tokens,[ref]$errors)
  $imports=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Import-Module'}, $true))
  $imports.Count | Should -Be 2
  $root=(Resolve-Path (Join-Path $PSScriptRoot '../../installer')).Path
  $ps=[powershell]::Create()
  try {
   foreach($import in $imports){
    $text=$import.Extent.Text -replace '\$PSScriptRoot',"'$root'"
    $ps.AddScript($text).AddStatement() | Out-Null
   }
   $ps.AddScript('Get-Command Wait-JawsSupervisorCandidate -ErrorAction Stop | Select-Object -ExpandProperty Name') | Out-Null
   $visible=@($ps.Invoke())
   $ps.HadErrors | Should -BeFalse
   $visible | Should -Be 'Wait-JawsSupervisorCandidate'
  } finally { $ps.Dispose() }
 }
 It 'parses all lifecycle PowerShell files' {
  foreach($relative in @('../../installer/modules/FoundrySupervisorReconciliation.psm1','../../installer/Reconcile-JawsSupervisorCandidate.ps1','../../installer/Release-JawsSupervisorCandidate.ps1','../../installer/Install-JawsStepC.ps1')){
   $t=$null;$errors=$null
   [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $relative),[ref]$t,[ref]$errors)|Out-Null
   @($errors).Count|Should -Be 0
  }
 }
}
