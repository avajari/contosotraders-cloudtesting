# Requires: Azure CLI login (az login) and correct subscription (az account set -s <subscriptionId>)
param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,            # Primary RG (e.g. contoso-traders-rgavanto)
    [Parameter(Mandatory=$true)][string]$Suffix,                       # Environment suffix (e.g. avanto)
    [string]$PrefixHyphenated = 'contoso-traders',                     # Base prefix used in names
    [string]$AksNodeResourceGroupName,                                 # Optional AKS node RG override (e.g. contoso-traders-aks-nodes-rgavanto)
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
function Write-Step($msg) { Write-Host "[stop-env] $msg" -ForegroundColor Cyan }
function Write-Skip($msg) { Write-Host "[skip] $msg" -ForegroundColor DarkYellow }
function Write-Ok($msg) { Write-Host "[ok] $msg" -ForegroundColor Green }
function Exec($cmd) { if ($WhatIf) { Write-Step "WHATIF: $cmd" } else { Write-Step "EXEC: $cmd"; Invoke-Expression $cmd } }

if (-not $AksNodeResourceGroupName) {
    # Derive node RG same as bicep variable: prefixHyphenated-aks-nodes-rg<suffix>
    $AksNodeResourceGroupName = "$PrefixHyphenated-aks-nodes-rg$Suffix"
}

$aksName = "$PrefixHyphenated-aks$Suffix" # managed cluster lives in primary RG
$afdProfile = "$PrefixHyphenated-afd$Suffix"
$fdImagesEp = "$PrefixHyphenated-images$Suffix"
$fdUiEp = "$PrefixHyphenated-ui$Suffix"
$fdUi2Ep = "$PrefixHyphenated-ui2$Suffix"
$productsApiApp = "$PrefixHyphenated-products$Suffix"
$cartsApiName = "$PrefixHyphenated-carts$Suffix"
$intCartsApiName = "$PrefixHyphenated-intcarts$Suffix"
$acrName = "contosotradersacr$Suffix"
$logAnalyticsName = "$PrefixHyphenated-loganalytics$Suffix"
$jumpboxVmName = 'jumpboxvm'

function ResourceExists($type, $name, $rg = $ResourceGroupName) {
    $json = az resource list -g $rg --query "[?type=='$type' && name=='$name']" -o json 2>$null
    return ($json | ConvertFrom-Json | Measure-Object).Count -gt 0
}

Write-Step "Stopping environment in resource group '$ResourceGroupName' (suffix=$Suffix)"

if (ResourceExists 'Microsoft.ContainerService/managedClusters' $aksName) {
    $state = az aks show -g $ResourceGroupName -n $aksName --query "powerState.code" -o tsv
    if ($state -eq 'Stopped') { Write-Skip "AKS already stopped" } else { Exec "az aks stop -g $ResourceGroupName -n $aksName" }
} else { Write-Skip "AKS cluster not found ($aksName)" }

# NOTE: Node pool resources (VMSS, LB, public IP, NSG) reside in the node resource group but are stopped implicitly when cluster is stopped.
# We can optionally surface info for user.
if (ResourceExists 'Microsoft.Network/publicIPAddresses' "$aksName" $AksNodeResourceGroupName) {
    Write-Step "Node RG ($AksNodeResourceGroupName) contains AKS infra; stopping cluster handles those resources."
}

$fdEndpoints = @($fdImagesEp, $fdUiEp, $fdUi2Ep)
foreach ($ep in $fdEndpoints) {
    try {
        $enabled = az afd endpoint show -g $ResourceGroupName --profile-name $afdProfile -n $ep --query "enabledState" -o tsv 2>$null
        if (-not $enabled) { Write-Skip "Front Door endpoint not found ($ep)" }
        elseif ($enabled -eq 'Disabled') { Write-Skip "Front Door endpoint $ep already disabled" }
        else { Exec "az afd endpoint update -g $ResourceGroupName --profile-name $afdProfile -n $ep --enabled-state Disabled" }
    } catch { Write-Skip "Front Door endpoint show failed ($ep): $($_.Exception.Message)" }
}

if (ResourceExists 'Microsoft.Web/sites' $productsApiApp) {
    $state = az webapp show -g $ResourceGroupName -n $productsApiApp --query state -o tsv
    if ($state -eq 'Stopped') { Write-Skip "WebApp already stopped" } else { Exec "az webapp stop -g $ResourceGroupName -n $productsApiApp" }
} else { Write-Skip "Products API WebApp not found" }

function ScaleContainerAppToZero($name) {
    $exists = az containerapp list -g $ResourceGroupName --query "[?name=='$name'] | length(@)" -o tsv 2>$null
    if ($exists -ne '1') { Write-Skip "Container App not found ($name)"; return }
    $currentMin = az containerapp show -n $name -g $ResourceGroupName --query "template.scale.minReplicas" -o tsv 2>$null
    if ($currentMin -eq '0') { Write-Skip "Container App $name already minReplicas=0" }
    else { Exec "az containerapp update -n $name -g $ResourceGroupName --min-replicas 0 --max-replicas 0" }
}
ScaleContainerAppToZero $cartsApiName
ScaleContainerAppToZero $intCartsApiName

if (ResourceExists 'Microsoft.OperationalInsights/workspaces' $logAnalyticsName) {
    $ing = az monitor log-analytics workspace show -g $ResourceGroupName -n $logAnalyticsName --query "publicNetworkAccessForIngestion" -o tsv
    if ($ing -eq 'Disabled') { Write-Skip "Log Analytics ingestion already disabled" } else { Exec "az monitor log-analytics workspace update -g $ResourceGroupName -n $logAnalyticsName --public-network-access-for-ingestion Disabled --public-network-access-for-query Disabled" }
} else { Write-Skip "Log Analytics workspace not found" }

if (ResourceExists 'Microsoft.Compute/virtualMachines' $jumpboxVmName) {
    $powerState = az vm get-instance-view -g $ResourceGroupName -n $jumpboxVmName --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code" -o tsv
    if ($powerState -eq 'PowerState/deallocated') { Write-Skip "Jumpbox VM already deallocated" } else { Exec "az vm deallocate -g $ResourceGroupName -n $jumpboxVmName" }
} else { Write-Skip "Jumpbox VM not found" }

Write-Ok "Stop sequence complete."