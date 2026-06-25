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

Status: Pending Step 3 completion.

## Step 5: Multi-turn

Status: Pending Step 4 completion.

## Step 6: Memory / External Knowledge

Status: Pending Step 5 completion.

## Step 7: Workflows

Status: Pending Step 6 completion.

## Step 8: Host Your Agent

Status: Pending Step 7 completion.
