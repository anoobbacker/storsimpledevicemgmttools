<#
.DESCRIPTION
    This script creates a StorSimple 8010/8020 cloud appliance.
    
    This quick start requires the Azure PowerShell module version 3.6 or later. 
    Run "Get-Module -ListAvailable AzureRM"" to find the version. 
    If you need to install or upgrade, see Install Azure PowerShell module from https://docs.microsoft.com/en-us/powershell/azure/install-azurerm-ps.

    Steps to execute the script: 
    ----------------------------
    1.  Open powershell, create a new folder & change directory to the folder.
            mkdir C:\scripts\StorSimpleSDKTools
            cd C:\scripts\StorSimpleSDKTools
    
    2. Download & execute the script from github. 
            wget https://github.com/anoobbacker/storsimpledevicemgmttools/raw/master/Create-StorSimpleCloudAppliance.ps1 -Out Authorize-ServiceEncryptionRollover.ps1
            .\Create-StorSimpleCloudAppliance.ps1 -CloudEnv [AzureCloud| -SubscriptionId [subcription id] -ResourceGroup [resource group] -Name [appliance name] -ModelNumber [8010|8020] -VirtualNetwork [vnet] -Subnet [subnet] -StorageAccount [storage name] -VmSize [vmsize] -RegistrationKey [key]
     ----------------------------   

.PARAMS
    CloudEnv: Input the Azure Cloud Environment.
    SubscriptionId: Input the ID of the subscription.
    ResourceGroup: Input the name of the resource group on which to authorize a device to change the service encryption key.
    Name: Input the name of the cloud appliance.
    ModelNumber: Input the appliance model number.
    VirtualNetwork: Input the name of the virtual network.
    Subnet: Input the name of the subnet of given virtual network.
    StorageAccount: Input the name of the storage account where the 8010/8020 appliance needs to be created.
    VmSize: Input the VM size. Possible values: Standard_DS3, Standard_DS3_v2, Standard_A3
    RegistrationKey: Input the registration key.
#>

param(
    [parameter(Mandatory = $true, HelpMessage = "Input the Azure Cloud Environment.")]
    [ValidateSet('AzureCloud', 'AzureChinaCloud','AzureUSGovernment', 'AzureGermanCloud')]
    [String] $CloudEnv,

    [parameter(Mandatory = $true, HelpMessage = "Input the ID of the subscription.")]
    [String] $SubscriptionId,

    [parameter(Mandatory=$true, HelpMessage="Input the name of the resource group where virtual netowrk and storage accoutn are present.")]
    [string] $ResourceGroup,

    [parameter(Mandatory=$true, HelpMessage="Input the name of the cloud appliance.")]
    [string] $Name,

    [parameter(Mandatory=$true, HelpMessage="Input the appliance model number.")]
    [ValidateSet('8010', '8020')]
    [string] $ModelNumber,

    [parameter(Mandatory=$true, HelpMessage="Input the name of the virtual network.")]
    [string] $VirtualNetwork,

    [parameter(Mandatory=$true, HelpMessage="Input the name of the subnet of given virtual network.")]
    [string] $Subnet,

    [parameter(Mandatory=$true, HelpMessage="Input the name of the storage account.")]
    [string] $StorageAccount,

    [parameter(Mandatory=$true, HelpMessage="Input the VM size.")]
    [ValidateSet('Standard_DS3', 'Standard_DS3_v2', 'Standard_A3')]
    [string] $VmSize,

    [parameter(Mandatory=$true, HelpMessage="Input the Registration key.")]
    [string] $RegistrationKey
    )


function ValidateInputs()
{
    $vnetLocation = $vnet.Location
    $saLocation = $storageAcc.Location
    if ($vnetLocation -notlike $saLocation)
    {
        #throw [System.ArgumentException] "Location of virtual netowrk is not same as of storage account"
    }
    if(!($vnet.Subnets | foreach {$_.Name -like $Subnet}))
    {
        throw [System.ArgumentException] "Subnet name passed could not be found in the virtual network"
    }
    if($ModelNumber -eq "8010")
    {
        if($storageAcc.Sku.Name -like "PremiumLRS")
        {
            throw [System.ArgumentException] "Premium LRS storage account type is not supported for 8010 model"
        }
        if($VmSize -notlike "Standard_A3")
        {
            throw [System.ArgumentException] "Only Standard A3 VM size is supported for 8010 model"
        }
    }
    if($ModelNumber -eq "8020")
    {
        if($storageAcc.Sku.Name -notlike "PremiumLRS")
        {
            throw [System.ArgumentException] "Only Premium LRS storage account type is supported for 8020 model"
        }
        if($VmSize -notlike "Standard_DS3" -and $VmSize -notlike "Standard_DS3_v2")
        {
            throw [System.ArgumentException] "Only Standard DS3 VM size(s) are supported for 8020 model"
        }
    }
}

# Print method
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

# Logon to Azure ARM
$AzureCloudenv = Get-AzureRmEnvironment $CloudEnv
$AzureAcct = Add-AzureRmAccount -Environment $AzureCloudenv
 
# Set context
$AzureRmCtx = Set-AzureRmContext -SubscriptionId $SubscriptionId

$vnet = Get-AzureRmVirtualNetwork -Name $VirtualNetwork -ResourceGroupName $ResourceGroup
$storageAcc = Get-AzureRmStorageAccount -Name $StorageAccount -ResourceGroupName $ResourceGroup

# Validate
ValidateInputs

$location = $vnet.Location
$subnetObj = $vnet.Subnets | where {$_.Name -like $Subnet}

$random = Get-Random
$nicName = $Name+$random
$containerName = $Name+$random
$availableIpAddr = $vnet | Test-AzureRmPrivateIPAddressAvailability -IPAddress $subnetObj.AddressPrefix.Split('/')[0]
$avaialbleIp = $availableIpAddr.AvailableIPAddresses[0]
$subnetId = $subnetObj.Id
$iPconfig = New-AzureRmNetworkInterfaceIpConfig -Name "ipconfig1" -PrivateIpAddressVersion IPv4 -PrivateIpAddress $avaialbleIp -SubnetId $subnetId
$nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroup -Location $location -IpConfiguration $iPconfig
$nicId = $nic.Id

$TrimmedRegKey=$RegistrationKey.Substring(0, $RegistrationKey.LastIndexOf(':'))
$customData = ""
$customData += "`r`nModelNumber=$ModelNumber"
$customData += "`r`nRegistrationKey=$TrimmedRegKey"
$customData += "`r`nTrackingId=$random"

$secpasswd = ConvertTo-SecureString "StorSim1StorSim1" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("hcstestuser", $secpasswd)

$vmConfig = New-AzureRmVMConfig -VMName $Name -VMSize $VmSize | `
    Set-AzureRmVMOperatingSystem -ComputerName $Name -Credential $cred -CustomData $customData -Windows | `
    Set-AzureRmVMOSDisk -Name "os" -VhdUri ($storageAcc.PrimaryEndpoints.Blob.ToString() + $containerName + "\os.vhd") -CreateOption FromImage | `
    Add-AzureRmVMDataDisk -Name "datadisk1" -DiskSizeInGB 1023 -VhdUri ($storageAcc.PrimaryEndpoints.Blob.ToString() + $containerName + "\datadisk1.vhd") -CreateOption empty -Lun 0 | `
    Add-AzureRmVMDataDisk -Name "datadisk2" -DiskSizeInGB 1023 -VhdUri ($storageAcc.PrimaryEndpoints.Blob.ToString() + $containerName + "\datadisk2.vhd") -CreateOption empty -Lun 1 | `
    Add-AzureRmVMDataDisk -Name "datadisk3" -DiskSizeInGB 1023 -VhdUri ($storageAcc.PrimaryEndpoints.Blob.ToString() + $containerName + "\datadisk3.vhd") -CreateOption empty -Lun 2 | `
    Add-AzureRmVMDataDisk -Name "datadisk4" -DiskSizeInGB 1023 -VhdUri ($storageAcc.PrimaryEndpoints.Blob.ToString() + $containerName + "\datadisk4.vhd") -CreateOption empty -Lun 3 | `
    Set-AzureRmVMSourceImage -PublisherName MicrosoftHybridCloudStorage -Offer StorSimple -Skus StorSimple-Garda-8000-Series -Version 9600.17820.170208 | `
    Add-AzureRmVMNetworkInterface -Id $nicId | Set-AzureRmVMBootDiagnostics -Disable

try {
    $vm = New-AzureRmVM -ResourceGroupName $ResourceGroup -Location $location -VM $vmConfig
    
    PrettyWriter "$Name successfully got created."
} catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}
