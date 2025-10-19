# Cost Management Scripts

These scripts let you temporarily suspend most billable activity for the Contoso Traders environment and later resume it.

## Scripts

- `iac/scripts/stop-env.ps1` – Disables or stops high-cost resources (AKS, Front Door endpoints, App Service, Container Apps, Log Analytics ingestion, Jumpbox VM deallocation).
- `iac/scripts/start-env.ps1` – Re-enables or restarts the resources to their original operational state.

Resources not directly stopped:
- Cosmos DB (serverless) – Charges only for consumed RU + storage; leaving it untouched retains data.
- SQL Databases (Basic tier already minimal) – No native pause for Basic SKU.
- Application Insights – Minimal cost at low ingestion; we disable ingestion indirectly via workspace if needed.
- Storage Accounts, Key Vault, ACR, Load Testing service, Dashboard, Chaos experiments – Low baseline cost; kept available.

## Prerequisites
1. Azure CLI installed.
2. Logged in: `az login`.
3. Correct subscription selected: `az account set -s <subscriptionId>`.
4. Resource group name and environment suffix (the 3–6 character suffix used in deployment).

## Usage
Environment in your case:
- Primary resource group: `contoso-traders-rgavanto`
- AKS node resource group: `contoso-traders-aks-nodes-rgavanto`
- Suffix: `avanto`
```powershell
# Dry run
./iac/scripts/stop-env.ps1 -ResourceGroupName contoso-traders-rgavanto -Suffix avanto -AksNodeResourceGroupName contoso-traders-aks-nodes-rgavanto -WhatIf

# Stop (execute)
./iac/scripts/stop-env.ps1 -ResourceGroupName contoso-traders-rgavanto -Suffix avanto -AksNodeResourceGroupName contoso-traders-aks-nodes-rgavanto

# Start (dry run)
./iac/scripts/start-env.ps1 -ResourceGroupName contoso-traders-rgavanto -Suffix avanto -AksNodeResourceGroupName contoso-traders-aks-nodes-rgavanto -WhatIf

# Start (execute)
./iac/scripts/start-env.ps1 -ResourceGroupName contoso-traders-rgavanto -Suffix avanto -AksNodeResourceGroupName contoso-traders-aks-nodes-rgavanto
```

## Notes
- Idempotent: Re-running stop or start skips resources already in desired state.
- Front Door endpoints are disabled, not deleted—no config loss.
- Container Apps scale to zero replicas (no compute charges) and are scaled back on start.
- AKS uses native stop/start (eliminates control plane + node charges while stopped).
- Jumpbox VM is deallocated (compute cost stops; OS disk persists).
- The ACR purge step is commented out; uncomment if you want automatic cleanup of old untagged images.
- Adjust naming logic if your deployment deviated from default prefix/suffix pattern.

## Optional Enhancements
- Tag-driven operations (filter by `Environment=<suffix>` and `Product=contoso-traders`).
- Scheduled auto-hibernate using GitHub Actions + `az cli` on weekends.
- Email/Teams notifications posting cost savings after stop script runs (estimate using pricing API).
- Parameterization for selective suspension (e.g. `-SkipFrontDoor`).

## Troubleshooting
- If scripts say a resource is not found, confirm the suffix matches your deployed names.
- Ensure you have sufficient RBAC rights to stop AKS and update endpoints (Contributor or above).
- For ACR purge, your account needs `AcrPush` rights.

---
Generated on 2025-10-17.