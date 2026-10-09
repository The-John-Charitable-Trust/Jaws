# Tutorial Step 1 — Read-only Azure Discovery and Tenant Inventory

JAWS installer Stage A separates identity preflight, tenant-scoped resource
inventory, target resource discovery, and persistent manifest ownership records.
The signed-in Entra identity provides authentication. Resource read operations
establish effective access instead of inferring authorization from role names.

The installer iterates through all enabled subscriptions available to the signed-in
identity in the selected subscription's tenant and records potential existing JAWS
resources. Detection is heuristic and not proof of installation or absence.

Stage A never creates, updates, or deletes Azure resources. Future Stage B adds
approved provisioning and configuration with role-specific authorization checks.

See `docs/installation/STEP-01-STAGE-A.md` and
`docs/verification/STEP-01-MANUAL-TESTS.md`.
