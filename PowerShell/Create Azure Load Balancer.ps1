Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module AzureRM -AllowClobber -Scope AllUsers

# Prompt for user and password.
Connect-AzureRMAccount

##############    Variables Definition - Start    ##############

# Create variables to store the location and the resource group name.
$resourceGroupName = 'AfikArviv'
$location = 'northeurope'

# Create the variables for the load balancer.
$lbPublicIPName = 'lb-es-pip'
$lbFrontendIPName = 'lb-fe-ip'
$backendPoolName = 'lb-be-pool'
$healthProbeName = 'lb-probe'
$lbRestRuleName = 'lb-es-rest-rule'
$lbNodeRuleName = 'lb-es-node-rule'
$lbHttpRuleName = 'lb-es-http-rule'

$lbName = 'es-lb'

$vNetName = 'afikVNet'
# The following parameters only needed for new vNet.
$vNetAddressPrefix = '10.0.0.0/16'
$subnetName = 'afikSubnet'
$subnetAddressPrefix = '10.0.0.0/24'

###############    Variables Definition - End    ###############

## Creating a virtual network (or using an existing).
# Check if the vNet already exists.
if ($vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq $vNetName}){
    write-host "The virtual network with the name '$vNetName' already exists. We will be Using it."
}else{
    # Create a subnet configuration.
    $subnetConfig = New-AzureRmVirtualNetworkSubnetConfig `
      -Name $subnetName `
      -AddressPrefix $subnetAddressPrefix
    
    # Create a virtual network.
    $vNet = New-AzureRmVirtualNetwork `
      -ResourceGroupName $resourceGroupName `
      -Location $location `
      -Name $vNetName `
      -AddressPrefix $vNetAddressPrefix `
      -Subnet $subnetConfig
}

# Create public IP Address.
# Check if the public IP already exists.
if ($lbPublicIP = Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq $lbPublicIPName}){
    write-host "The public IP with the name '$lbPublicIPName' already exists. Trying to use it."
} else{
    # Create a new public IP address.
    $lbPublicIP = New-AzureRmPublicIpAddress `
      -ResourceGroupName $resourceGroupName `
      -Location $location `
      -AllocationMethod Static `
      -Name $lbPublicIPName
}

# Create front-end IP.
$lbFrontendIP = New-AzureRmLoadBalancerFrontendIpConfig `
  -Name $lbFrontendIPName `
  -PublicIpAddress $lbPublicIP

# Create Backend address poll.
$backendPool = New-AzureRmLoadBalancerBackendAddressPoolConfig `
  -Name $backendPoolName

# Create a helath probe.
$healthProbe = New-AzureRmLoadBalancerProbeConfig `
  -Name $healthProbeName `
  -RequestPath healthcheck.aspx `
  -Protocol Http `
  -Port 80 `
  -IntervalInSeconds 16 `
  -ProbeCount 2

# Create load balancer rule for the Rest communication.
$lbRestRule = New-AzureRmLoadBalancerRuleConfig `
  -Name $lbRestRuleName `
  -FrontendIpConfiguration $lbFrontendIP `
  -BackendAddressPool $backendPool `
  -Protocol Tcp `
  -FrontendPort 9200 `
  -BackendPort 9200 `
  -Probe $healthProbe `
  -IdleTimeoutInMinutes 15
  

# Create a load balancer.
# Check if there is a load balancer with that name.
if (Get-AzureRmLoadBalancer -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq $lbName}){
    Write-Host "The load balancer with that name already exists."
}else{
    # Create a new load balancer.
    $eslb = New-AzureRmLoadBalancer `
      -ResourceGroupName $resourceGroupName `
      -Name $lbName `
      -Location $location `
      -FrontendIpConfiguration $lbFrontendIP `
      -BackendAddressPool $backendPool `
      -Probe $healthProbe `
      -LoadBalancingRule $lbRestRule
}

# Add a load balancer rule for the elastic node communication.
$eslb | Add-AzureRmLoadBalancerRuleConfig `
  -Name $lbNodeRuleName `
  -FrontendIpConfiguration $lbFrontendIP `
  -BackendAddressPool $backendPool `
  -Protocol Tcp `
  -FrontendPort 9300 `
  -BackendPort 9300 `
  -Probe $healthProbe `
  -IdleTimeoutInMinutes 15

# Add a load balancer rule for the http mmunication.
$eslb | Add-AzureRmLoadBalancerRuleConfig `
  -Name $lbHttpRuleName `
  -FrontendIpConfiguration $lbFrontendIP `
  -BackendAddressPool $backendPool `
  -Protocol Tcp `
  -FrontendPort 80 `
  -BackendPort 80 `
  -Probe $healthProbe `
  -IdleTimeoutInMinutes 15

# Reload changes to the load balancer.
$eslb | Set-AzureRmLoadBalancer
