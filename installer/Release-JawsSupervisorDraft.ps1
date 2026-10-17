# Retired. This script targeted one historical draft and could release a different
# image from the reconciled candidate path. It performs no Azure writes.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Release','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeTrafficAndInferenceCharges
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
throw 'JAWS-SUP-REL-010: Release-JawsSupervisorDraft.ps1 is retired. Use Release-JawsSupervisorCandidate.ps1. Supervisor v1 is left unchanged and no version is posted.'
