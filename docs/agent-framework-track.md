# JAWS Agent Framework Track

This document tracks the clean JAWS implementation against the Microsoft Agent Framework documentation and the JAWS-specific platform phases required for the operations scenario.

## Step 1: Your First Agent

Status: Released as `v0.1`.

Planned deliverables:

- Minimal C# first-agent implementation
- Local API health and first-agent execution endpoints
- Local development configuration model
- Step 1 tutorial and expected results
- Step 1 test cases

## Step 2: Add MCP Server

Status: Released as `v0.2`.

Planned deliverables:

- Local custom MCP endpoint at `/mcp`
- MCP registry and read-only status tools
- JSON-RPC handling for `initialize`, `tools/list`, and `tools/call`
- Step 2 tutorial and expected results
- Step 2 test cases

## Step 3: Secure MCP Server

Status: Released as `v0.3`.

Planned deliverables:

- MCP security metadata for read-only and write-capable tools
- JSON-RPC request validation
- Safe MCP error responses with correlation IDs
- Schema-based rejection of undeclared tool arguments
- Explicit write-tool blocking unless writes are enabled through an approval path
- CoSAI MCP Security-aligned Step 3 tutorial and expected results
- Step 3 security test cases

## Step 4: Add Tools

Status: Released as `v0.4`.

Planned deliverables:

- Demo-scoped Azure, Datadog, ServiceNow, and JAWS extensibility tools registered behind MCP
- Read/write tool classification retained from the secured MCP boundary
- Role-agent allowed tools aligned with the MCP registry
- JSON job-description extensibility explained and validated
- Write-capable Datadog and ServiceNow tools registered but blocked until workflow approval
- Tool contracts documented as agent-computer interface boundaries for purpose, provider, parameters, read/write classification, and evidence shape
- Step 4 tutorial and expected results
- Step 4 test cases

## Step 5: Multi-Turn Conversations

Status: Released as `v0.5`.

Planned deliverables:

- Agent Framework session reuse through `AgentSession`
- Local conversation IDs and turn metadata for API calls
- Conversation reset support for the local API
- Objective validation that does not depend on deterministic model text
- Step 5 tutorial and expected results
- Step 5 test cases

## Step 6: Memory / External Knowledge

Status: Pending release `v0.6`.

## Step 7: Workflows

Status: Pending release `v0.7`.

## Step 8: Host Your Agent

Status: Pending release `v0.8`.

## Step 9: Teams App Integration

Status: Pending release `v0.9`.

## Step 10: End-To-End JAWS Operations Scenario

Status: Pending release `v1.0`.
