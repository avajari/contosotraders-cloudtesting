# Requires: Azure CLI login (az login) and correct subscription (az account set -s <subscriptionId>)
param(
    [Parameter(Mandatory=$true)][string]$ResourceGroupName,            # Primary RG (e.g. contoso-traders-rgavanto)
    [Parameter(Mandatory=$true)][string]$Suffix,                       # Environment suffix (e.g. avanto)
    [string]$PrefixHyphenated = 'contoso-traders',                     # Base prefix used in names
    [string]$AksNodeResourceGroupName,                                 # Optional AKS node RG override (e.g. contoso-traders-aks-nodes-rgavanto)
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
function Write-Step($msg) { Write-Host "[start-env] $msg" -ForegroundColor Cyan }
function Write-Skip($msg) { Write-Host "[skip] $msg" -ForegroundColor DarkYellow }
function Write-Ok($msg) { Write-Host "[ok] $msg" -ForegroundColor Green }
function Exec($cmd) { if ($WhatIf) { Write-Step "WHATIF: $cmd" } else { Write-Step "EXEC: $cmd"; Invoke-Expression $cmd } }

if (-not $AksNodeResourceGroupName) {
    $AksNodeResourceGroupName = "$PrefixHyphenated-aks-nodes-rg$Suffix"
}

$aksName = "$PrefixHyphenated-aks$Suffix"
$afdProfile = "$PrefixHyphenated-afd$Suffix"
$fdImagesEp = "$PrefixHyphenated-images$Suffix"
$fdUiEp = "$PrefixHyphenated-ui$Suffix"
$fdUi2Ep = "$PrefixHyphenated-ui2$Suffix"
$productsApiApp = "$PrefixHyphenated-products$Suffix"
$cartsApiName = "$PrefixHyphenated-carts$Suffix"
$intCartsApiName = "$PrefixHyphenated-intcarts$Suffix"
$logAnalyticsName = "$PrefixHyphenated-loganalytics$Suffix"
$jumpboxVmName = 'jumpboxvm'

function ResourceExists($type, $name, $rg = $ResourceGroupName) {
    $json = az resource list -g $rg --query "[?type=='$type' && name=='$name']" -o json 2>$null
    return ($json | ConvertFrom-Json | Measure-Object).Count -gt 0
}

Write-Step "Starting environment in resource group '$ResourceGroupName' (suffix=$Suffix)"

if (ResourceExists 'Microsoft.ContainerService/managedClusters' $aksName) {
    $state = az aks show -g $ResourceGroupName -n $aksName --query "powerState.code" -o tsv
    if ($state -eq 'Running') { Write-Skip "AKS already running" } else { Exec "az aks start -g $ResourceGroupName -n $aksName" }
} else { Write-Skip "AKS cluster not found ($aksName)" }

if (ResourceExists 'Microsoft.Network/publicIPAddresses' "$aksName" $AksNodeResourceGroupName) {
    Write-Step "Node RG ($AksNodeResourceGroupName) AKS infra will come online with cluster start."
}

$fdEndpoints = @($fdImagesEp, $fdUiEp, $fdUi2Ep)
foreach ($ep in $fdEndpoints) {
    try {
        $enabled = az afd endpoint show -g $ResourceGroupName --profile-name $afdProfile -n $ep --query "enabledState" -o tsv 2>$null
        if (-not $enabled) { Write-Skip "Front Door endpoint not found ($ep)" }
        elseif ($enabled -eq 'Enabled') { Write-Skip "Front Door endpoint $ep already enabled" }
        else { Exec "az afd endpoint update -g $ResourceGroupName --profile-name $afdProfile -n $ep --enabled-state Enabled" }
    } catch { Write-Skip "Front Door endpoint show failed ($ep): $($_.Exception.Message)" }
}

if (ResourceExists 'Microsoft.Web/sites' $productsApiApp) {
    $state = az webapp show -g $ResourceGroupName -n $productsApiApp --query state -o tsv
    if ($state -eq 'Running') { Write-Skip "WebApp already running" } else { Exec "az webapp start -g $ResourceGroupName -n $productsApiApp" }
} else { Write-Skip "Products API WebApp not found" }

function ScaleContainerAppUp($name, $min=1, $max=10) {
    $exists = az containerapp list -g $ResourceGroupName --query "[?name=='$name'] | length(@)" -o tsv 2>$null
    if ($exists -ne '1') { Write-Skip "Container App not found ($name)"; return }
    $currentMin = az containerapp show -n $name -g $ResourceGroupName --query "template.scale.minReplicas" -o tsv 2>$null
    if ($currentMin -eq $min) { Write-Skip "Container App $name already minReplicas=$min" }
    else { Exec "az containerapp update -n $name -g $ResourceGroupName --min-replicas $min --max-replicas $max" }
}
ScaleContainerAppUp $cartsApiName 1 10
ScaleContainerAppUp $intCartsApiName 1 3

if (ResourceExists 'Microsoft.OperationalInsights/workspaces' $logAnalyticsName) {
    $ing = az monitor log-analytics workspace show -g $ResourceGroupName -n $logAnalyticsName --query "publicNetworkAccessForIngestion" -o tsv
    if ($ing -eq 'Enabled') { Write-Skip "Log Analytics ingestion already enabled" } else { Exec "az monitor log-analytics workspace update -g $ResourceGroupName -n $logAnalyticsName --public-network-access-for-ingestion Enabled --public-network-access-for-query Enabled" }
} else { Write-Skip "Log Analytics workspace not found" }

if (ResourceExists 'Microsoft.Compute/virtualMachines' $jumpboxVmName) {
    $powerState = az vm get-instance-view -g $ResourceGroupName -n $jumpboxVmName --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code" -o tsv
    if ($powerState -eq 'PowerState/running') { Write-Skip "Jumpbox VM already running" } else { Exec "az vm start -g $ResourceGroupName -n $jumpboxVmName" }
} else { Write-Skip "Jumpbox VM not found" }

Write-Ok "Start sequence complete."