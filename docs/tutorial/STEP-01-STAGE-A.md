# Tutorial Step A — Getting Started with Azure Discovery

This introduction is for a **new JAWS customer** with an Azure subscription and no JAWS infrastructure. Step A has four activities: **(1) authenticate, (2) inventory, (3) reconcile existing installations only, (4) verify read-only evidence**. Nothing in Step A should create Azure resources.

A new customer's subscription may contain **zero** JAWS resources. That is a valid discovery outcome. The current JAWS v0.4.6 state-first installer cannot automatically initialize a new installation state; first-time installation support is an outstanding engineering deliverable.

**Follow the complete, numbered walkthrough:** [Step A installation tutorial](../installation/STEP-01-STAGE-A.md).

**Expected results for completion:** Confirm the intended tenant/subscription, retrieve a permitted resource inventory (which may be empty), preserve Azure configuration, and document zero cloud writes. If JAWS already exists and you have the corresponding state, verify the JAWS tenant scan, target comparison and generated reports.

**Acceptance criteria:** A-01 authentication, A-02 scoped inventory, A-03 existing-state reconciliation when applicable, A-04 no Azure changes, A-05 documented evidence, A-06 greenfield installer release gate. **Existing-development reconciliation passed previously; automated clean-subscription installation discovery is not yet accepted.**

For executable shortcuts and software links, see the [Quick Start](../status/quick-start.html). For mapped Microsoft documentation and tests, see [Step A references](../status/references.html#step-A).
