Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module AzureRM -AllowClobber -Scope AllUsers

# Prompt for user and password.
Connect-AzureRMAccount

##############    Variables Definition - Start    ##############

# Create variables to store the location, the resource group name and the availability set name.
$location = 'northeurope'
$resourceGroupName = 'AfikArviv'
$availabilitySetName = 'esAvailSet'

# Create variables to store the storage info (storage account name, storage account SKU  and the container name)
$storageAccountName = "afikstorageaccount"    #must contain lower case and digits only.
$skuName = "Standard_LRS"
$containerName = 'osdisks'    #must contain lower case and digits only.

# Create variables to store the network security group and rules names
$nsgName = "esNSG"
$nsgRuleSSHName = "sshNSGRule"
$nsgRuleEsRestName = "esRestNSGRule"
$nsgRuleEsNodeName = "esNodeNSGRule"
$nshRuleHttpName = "esHttpNSGRule"

# Create variables for VM user, password and size.
$vmUser = 'testuser'
$vmPassword = 'Password1234!'
$vmSize = 'Standard_Ds1_v2'

# Create vatiables for the VM(s) name(s) and amount of node.
$vmName1 = "es-c77-m-1"
$vmName2 = "es-c77-m-2"
$vmName3 = "es-c77-m-3"
$numOfNodes = 3

# Create variables for the disks (data disks and OS disk).
$strSizeNum = 64
[int]$diskSizeInGB = [convert]::ToInt32($strSizeNum, 10)

$dataDiskType = 'StandardSSD_LRS'
$osDiskName = 'OsDisk'

# Creating a 'dataDiskName<X>' variable for each of the vmName<X> variable (X represent a number).
for ($i=1; $i -le $numOfNodes; $i++)
{
    $cur_val = Get-Variable -Name "vmName$i" -ValueOnly
    New-Variable -Name "dataDiskName$i" -Value "$($cur_val)_datadisk_1"
 }


# Create the variables for the load balancer.
$lbPublicIPName = 'lb-es-pip'
$lbFrontendIPName = 'lb-fe-ip'
$backendPoolName = 'lb-be-pool'
$healthProbeName = 'lb-probe'
$lbRestRuleName = 'lb-es-rest-rule'
$lbNodeRuleName = 'lb-es-node-rule'
$lbHttpRuleName = 'lb-es-http-rule'
$lbName = 'es-lb'

# Create the variable for the virtual network.
$vNetName = 'afikVNet'
# The following parameters only needed for new vNet.
$vNetAddressPrefix = '10.0.0.0/16'
$subnetName = 'afikSubnet'
$subnetAddressPrefix = '10.0.0.0/24'

###############    Variables Definition - End    ###############

#############    Load Balancer Creation - Start    #############

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

##############    Load Balancer Creation - End    ##############

#########    Resources Creation for the VMs - Start    #########

            #### Storage resources ####

# Create a new storage account.
if ($storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName | Where-Object { $_.StorageAccountName -eq $storageAccountName}){
    write-host "The storage account with the name '$storageAccountName' already exists. We'll try to use it."
}else{
    $storageAccount = New-AzureRMStorageAccount `
      -Location $location `
      -ResourceGroupName $resourceGroupName `
      -skuName $skuName `
      -Name $storageAccountName
    
    Set-AzureRmCurrentStorageAccount `
      -Name $storageAccountName `
      -ResourceGroupName $resourceGroupName
}


# Create a storage container to store the VM image.
if ($container = Get-AzureRmStorageContainer -ResourceGroupName $resourceGroupName -StorageAccountName $storageAccountName | Where-Object { $_.Name -eq $containerName}){
    write-host "The container name with the name '$containerName' under the storage account '$storageAccountName' already exists. We'll try to use it."
}else{
    $contianer = New-AzureRmStorageContainer `
    -ResourceGroupName $resourceGroupName `
    -Name $containerName `
    -PublicAccess None `
    -StorageAccountName $storageAccountName
}

            #### Networking resources ####

# Create a public IP address and specify a DNS name.
for ($i=1; $i -le $numOfNodes; $i++)
{
    # Get the current VM name.
    $cur_vm_name = Get-Variable -Name "vmName$i" -ValueOnly

    if (Get-AzureRmPublicIpAddress -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq "$($cur_vm_name)-PublicIp"}){
        write-host "The public IP with the name '$($cur_vm_name)-PublicIp' already exists. Aborting."
        # TODO - Delete public IPs that we already created untill the one that already exists.
        exit
    }else{
        New-Variable -Name "publicIP$i" -Value (New-AzureRmPublicIpAddress `
          -ResourceGroupName $resourceGroupName `
          -Location $location `
          -AllocationMethod Static `
          -IdleTimeoutInMinutes 4 `
          -Name "$($cur_vm_name)-pip")
    }
 }
  
            #### NSG resources ####

# Create inbound network security group rules.
if ($esNsg = Get-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq $nsgName}){
    Write-Host "The network security group with the name '$nsgName' already exists. We'll try to use it."
}else{
    # Create an inbound network security group rule for port 22 (SSH).
    $nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig `
    -Name $nsgRuleSSHName `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1000 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 22 `
    -Access Allow
    
    # Create an inbound network security group rule for port 9200 (ES Rest).
    $nsgRuleEsRest = New-AzureRmNetworkSecurityRuleConfig `
    -Name $nsgRuleEsRestName `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1001 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 9200 `
    -Access Allow
    
    # Create an inbound network security group rule for port 9300 (ES Node).
    $nsgRuleEsNode = New-AzureRmNetworkSecurityRuleConfig `
    -Name $nsgRuleEsNodeName `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1002 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 9300 `
    -Access Allow

    # Create an inbound network security group rule for port 80 (Http)
    $nsgRuleEsHttp = New-AzureRmNetworkSecurityRuleConfig `
    -Name $nshRuleHttpName `
    -Protocol Tcp `
    -Direction Inbound `
    -Priority 1003 `
    -SourceAddressPrefix * `
    -SourcePortRange * `
    -DestinationAddressPrefix * `
    -DestinationPortRange 80 `
    -Access Allow
    

    # Create a network security group.
    $esNsg = New-AzureRmNetworkSecurityGroup `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -Name $nsgName `
    -SecurityRules $nsgRuleSSH,$nsgRuleEsRest,$nsgRuleEsNode,$nsgRuleEsHttp
}

            #### Network card ####

# Create a virtual network card and associate it with public IP address and NSG.
for ($i=1; $i -le $numOfNodes; $i++)
{
    # Get the current VM name.
    $cur_vm_name = Get-Variable -Name "vmName$i" -ValueOnly
    # Get the cuurent public IP object.
    $cur_pub_ip = Get-Variable -Name "publicIP$i" -ValueOnly
    
    if (Get-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq "esM$($i)Nic"}){
        write-host "The network interface with the name 'esM$($i)Nic' already exists. Aborting."
        # TODO - Delete network interfaces that we already created untill the one that already exists.
        exit
    }else{
        New-Variable -Name "esM$($i)Nic" -Value (New-AzureRmNetworkInterface `
          -Name "esM$($i)Nic" `
          -ResourceGroupName $resourceGroupName `
          -Location $location `
          -SubnetId $vNet.Subnets[0].Id `
          -PublicIpAddressId $cur_pub_ip.Id `
          -NetworkSecurityGroupId $esNsg.Id)
    }
 }

            #### Availability set ####

# Create an availability set.
$availSet = New-AzureRmAvailabilitySet `
  -ResourceGroupName $resourceGroupName `
  -Name $availabilitySetName `
  -Location $location `
  -Sku 'Aligned' `
  -PlatformFaultDomainCount 2 `
  -PlatformUpdateDomainCount 2

            #### Data disk ####

# Create a data disk configuration.
$dataDiskConf = New-AzureRmDiskConfig `
  -Location $location `
  -CreateOption Empty `
  -DiskSizeGB $diskSizeInGB `
  -SkuName $dataDiskType `
  -OsType Linux

# Create the data disks.
# Create 1 disk for each vm.
for ($i=1; $i -le $numOfNodes; $i++)
{
    # Get the current VM name.
    $cur_vm_name = Get-Variable -Name "vmName$i" -ValueOnly
    # Get the current data disk name for the current vm.
    $cur_dataDisk_name = Get-Variable -Name "dataDiskName$i" -ValueOnly

    if (Get-AzureRmDisk -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq $cur_dataDisk_name}){
        Write-Host "The disk '$cur_dataDisk_name' already exists. We'll try use it."
        New-Variable -Name "dataDisk_$cur_vm_name" -Value (Get-AzureRmDisk -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq $cur_dataDisk_name})
    }else{
        New-Variable -Name "dataDisk_$cur_vm_name" -Value (New-AzureRmDisk `
          -ResourceGroupName $resourceGroupName `
          -DiskName $cur_dataDisk_name `
          -Disk $dataDiskConf)
    }
 }

##########    Resources Creation for the VMs - Start    ##########

##################    VM Creation - Start    ##################

# Define a credential object
$securePassword = ConvertTo-SecureString $vmPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($vmUser, $securePassword)

# Create the VM configuration object and the actual vm.
for ($i=1; $i -le $numOfNodes; $i++)
{
    # Get the current VM name.
    $cur_vm_name = Get-Variable -Name "vmName$i" -ValueOnly
    # Get the current data disk name for the current vm.
    $cur_dataDisk_name = Get-Variable -Name "dataDiskName$i" -ValueOnly
    # Get the current nic object for the current vm.
    $cur_nic = Get-Variable -Name "esM$($i)Nic" -ValueOnly
    # Get the current data disk object for the current vm.
    $cur_dataDisk = Get-Variable -Name "dataDisk_$cur_vm_name" -ValueOnly

    if (Get-AzureRmVM -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -eq $cur_vm_name}){
        write-host "The virtual machine with the name $cur_vm_name already exists. Aborting."
        # TODO - Delete the VMs  that we already created untill the one that already exists.
        exit
    }else{
        New-Variable -Name "virtualMachine$i" -Value (New-AzureRmVMConfig `
          -VMName $cur_vm_name `
          -VMSize $vmSize `
          -AvailabilitySetId $availSet.Id)
        
        # Get the current vm configuration object.
        $cur_vm_conf_obj = Get-Variable -Name virtualMachine$i -ValueOnly

        # Set the Operating system configuration.
        Set-Variable -Name $cur_vm_conf_obj -Value (Set-AzureRmVMOperatingSystem `
          -VM $cur_vm_conf_obj `
          -Linux `
          -ComputerName "$cur_vm_name" `
          -Credential $cred)

        # Set the source image.
        Set-Variable -Name $cur_vm_conf_obj -Value (Set-AzureRmVMSourceImage `
          -VM $cur_vm_conf_obj `
          -PublisherName "OpenLogic" `
          -Offer "CentOS" `
          -Skus "7.7" `
          -Version "latest")

        #TODO - Check if the osDiskUri already exists.
        # {X} represents the parameter given later.
        $cur_osDisk_name = "$cur_vm_name-$osDiskName"
        $osDiskUri = "{0}$containerName/{1}-{2}.vhd" -f `
          $storageAccount.PrimaryEndpoints.Blob.ToString(),`
          $cur_vm_name.ToLower(), `
          $cur_osDisk_name

        # Set the operating system disk properties on a VM.
        Set-Variable -Name $cur_vm_conf_obj -Value (Set-AzureRmVMOSDisk `
          -VM $cur_vm_conf_obj `
          -Name $cur_osDisk_name `
           -CreateOption fromImage)


        # Add the NIC to the configuration of the new vm.
        Set-Variable -Name $cur_vm_conf_obj -Value (Add-AzureRmVMNetworkInterface `
          -VM $cur_vm_conf_obj `
          -Id $cur_nic.Id)

        # Attach the data disk to the configuration of the new vm.
        Set-Variable -Name $cur_vm_conf_obj -Value (Add-AzureRmVMDataDisk `
          -Vm $cur_vm_conf_obj `
          -Name $cur_dataDisk_name `
          -CreateOption Attach `
          -ManagedDiskId $cur_dataDisk.Id `
          -Lun 1)

        # Create the VM.
        New-AzureRmVM `
          -ResourceGroupName $resourceGroupName `
          -Location $location `
          -VM $cur_vm_conf_obj
    }
}

###################    VM Creation - End    ###################

#############    Connect Load Balancer - Start    #############

## Associate the NIC(s) of the VM(s) to the Loopback BackendAddressPool.

# Getting the load balancer object.
if ($lb = Get-AzureRmLoadBalancer -ResourceGroupName $resourceGroupName | Where-Object {$_.Name -eq $lbName}){
    # Getting the backend pool object.
    if ($backendPool = Get-AzureRmLoadBalancerBackendAddressPoolConfig -LoadBalancer $lb | Where-Object {$_.Name -eq $backendPoolName}){
        for ($i=1; $i -le $numOfNodes; $i++) {
            # Get the current NIC object.
            $cur_nic = Get-Variable -Name "esM$($i)Nic" -ValueOnly
            
            # Associate to the backend pool.
            $cur_nic.IpConfigurations[0].LoadBalancerBackendAddressPools.Add($backendpool)

            # Update the changes to the NIC.
            $cur_nic | Set-AzureRmNetworkInterface
        }

    }else{
        Write-Host "The backend pool with the name '$backendPoolName' does not exists under the load balancer '$lbName'."
        Write-Host "Cannot associate the NIC(s) of the VM(s) to the load balancer."
    }

}else{
    Write-Host "The load balancer with the name '$lbName' does not exists under the resource group '$resourceGroupName'."
    Write-Host "Cannot associate the NIC(s) of the VM(s) to the load balancer."
}

##############    Connect Load Balancer - End    ##############