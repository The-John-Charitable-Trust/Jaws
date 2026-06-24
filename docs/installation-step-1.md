# Step 1 Installation

Release `0.1` maps to Microsoft Agent Framework Step 1: Your First Agent.

## Local SDK Requirement

Release `0.1` targets `net10.0` and requires the .NET 10 SDK for local build and test execution.

## What This Installs

Step 1 installs the minimum JAWS API surface required to prove that the platform can call the configured Azure AI Foundry or Azure OpenAI model deployment through the Microsoft Agent Framework.

It does not install tools, MCP, Teams, RAG, workflows, Datadog, or ServiceNow execution. Those capabilities are added in later releases.

## Bootstrap File

The repository includes `config/bootstrap.example.json` as documentation for the required inputs. During installation, create a local bootstrap file with real tenant and deployment values. Do not commit the local bootstrap file.

Required Step 1 values:

- Azure subscription ID
- Azure tenant ID
- Azure region
- naming inputs
- agent endpoint
- model deployment name
- agent name
- agent instructions

Secrets and credentials must be stored in Azure Key Vault or Key Vault-backed application settings, not in the bootstrap JSON.

## Validation

After deployment, validate the hosted API:

```powershell
Invoke-RestMethod -Method Get -Uri "https://<jaws-api-host>/health"
```

Then validate the Step 1 agent:

```powershell
Invoke-RestMethod -Method Post -Uri "https://<jaws-api-host>/api/agent/step1/run" `
  -ContentType "application/json" `
  -Body '{ "message": "What does JAWS Step 1 prove?" }'
```

Expected result:

- `/health` returns `status = healthy` when configuration is complete.
- `/api/agent/step1/run` returns an answer from `JawsStep1Agent`.
- Response metadata includes `release = 0.1` and `documentationStep = Step 1: Your First Agent`.


