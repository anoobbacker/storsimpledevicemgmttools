<#
.DESCRIPTION 
    This runbook creates a script and stores it in a storage account. This script  will connect the iSCSI target and mount the volumes on the VM after a failover. 
    It then uses the Custom VM Script Extension to run the script on the VM.

.DEPENDENCIES
    Azure VM agent should be installed in the VM before this script is executed 
    If it is not already installed, install it inside the VM from http://aka.ms/vmagentwin

.ASSETS 
    [You can choose to encrypt these assets ]

    The following have to be added with the Recovery Plan Name as a prefix, eg - TestPlan-StorSimRegKey [where TestPlan is the name of the recovery plan]
    [All these are String variables]

    BaseUrl: The resource manager url of the Azure cloud. Get using "Get-AzureRmEnvironment | Select-Object Name, ResourceManagerUrl" cmdlet.
    'RecoveryPlanName'-ResourceGroupName: The name of the resource group on which to read storsimple virtual appliance info
    'RecoveryPlanName'-ManagerName: The name of the StorSimple resource manager
    'RecoveryPlanName'-DeviceName: The device which has to be failed over
    'RecoveryPlanName'-DeviceIpAddress: The IP address of the device
    'RecoveryPlanName'-TargetDeviceName: The Device on which the containers are to be failed over (the one which needs to be switched on)
    'RecoveryPlanName'-TargetDeviceIpAddress: The IP address of the target device
    'RecoveryPlanName'-StorageAccountName: The storage account name in which the script will be stored
    'RecoveryPlanName'-StorageAccountKey: The access key for the storage account
    'RecoveryPlanName'-VMGUIDS: 
        Upon protecting a VM, ASR assigns every VM a unique ID which gives the details of the failed over VM. 
        Copy it from the Protected Item -> Protection Groups -> Machines -> Properties in the Recovery Services tab.
        In case of multiple VMs then add them as a comma separated string
#>

workflow Mount-Volumes-After-Failover
{  
    Param 
    ( 
        [parameter(Mandatory=$true)] 
        [Object]
        $RecoveryPlanContext
    )

    $PlanName = $RecoveryPlanContext.RecoveryPlanName

    $ResourceGroupName = Get-AutomationVariable -Name "$PlanName-ResourceGroupName" 
    if ($ResourceGroupName -eq $null) 
    { 
        throw "The ResourceGroupName asset has not been created in the Automation service."  
    }
    
    $ManagerName = Get-AutomationVariable -Name "$PlanName-ManagerName" 
    if ($ManagerName -eq $null) 
    { 
        throw "The ManagerName asset has not been created in the Automation service."
    }
     
    $DeviceName = Get-AutomationVariable -Name "$PlanName-DeviceName"
    if ($DeviceName -eq $null)
    { 
        throw "The DeviceName asset has not been created in the Automation service."  
    }
    
    $TargetDeviceName = Get-AutomationVariable -Name "$PlanName-TargetDeviceName" 
    if ($TargetDeviceName -eq $null) 
    { 
        throw "The TargetDeviceName asset has not been created in the Automation service."  
    }
     
    $DeviceIpAddress = Get-AutomationVariable -Name "$PlanName-DeviceIpAddress"
    if ($DeviceIpAddress -eq $null) 
    { 
        throw "The DeviceIpAddress asset has not been created in the Automation service."  
    }
    
    $TargetDeviceIpAddress = Get-AutomationVariable -Name "$PlanName-TargetDeviceIpAddress" 
    if ($TargetDeviceIpAddress -eq $null) 
    { 
        throw "The TargetDeviceIpAddress asset has not been created in the Automation service."  
    }
    
    $StorageAccountName = Get-AutomationVariable -Name "$PlanName-StorageAccountName" 
    if ($StorageAccountName -eq $null) 
    { 
        throw "The StorageAccountName asset has not been created in the Automation service."  
    }
    # Convert to lowercase
    $StorageAccountName = $StorageAccountName.ToLower()

    $StorageAccountKey = Get-AutomationVariable -Name "$PlanName-StorageAccountKey" 
    if ($StorageAccountKey -eq $null) 
    { 
        throw "The StorageAccountKey asset has not been created in the Automation service."  
    }
   
    $VMGUIDString = Get-AutomationVariable -Name "$PlanName-VMGUIDS" 
    if ($VMGUIDString -eq $null) 
    { 
        throw "The VMGUIDS asset has not been created in the Automation service."  
    }
    $VMGUIDS =  @($VMGUIDString.Split(",").Trim())
     
    $BaseUrl = Get-AutomationVariable -Name "BaseUrl"
    if ($BaseUrl -eq $null) 
    { 
        throw "The BaseUrl asset has not been created in the Automation service."  
    }

    $ClientCertificate = Get-AutomationCertificate -Name "AzureRunAsCertificate"
    if ($ClientCertificate -eq $null)
    {
         throw "The AzureRunAsCertificate asset has not been created in the Automation service."
    }

    $ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"
    if ($ServicePrincipalConnection -eq $null)
    {
         throw "The AzureRunAsConnection asset has not been created in the Automation service."
    }

    # Get the SubscriptionId, TenantId & ApplicationId
    $SubscriptionId = $ServicePrincipalConnection.SubscriptionId
    $TenantId = $ServicePrincipalConnection.TenantId
    $ClientId = $ServicePrincipalConnection.ApplicationId
    
    $ScriptContainer = "ss-asr-scriptcontainer"
    $ScriptPSFileName = "iscsi-VMName-Timestamp.ps1"
    $SLEEPTIMEOUT = 10    # Value in seconds

    InlineScript 
    {
        $BaseUrl = $Using:BaseUrl
        $SubscriptionId = $Using:SubscriptionId
        $TenantId = $Using:TenantId
        $ClientId = $Using:ClientId
        $ResourceGroupName = $Using:ResourceGroupName
        $ManagerName = $Using:ManagerName
        $ClientCertificate = $Using:ClientCertificate
        $DeviceName = $Using:DeviceName
        $TargetDeviceName = $Using:TargetDeviceName
        $DeviceIpAddress = $Using:DeviceIpAddress
        $TargetDeviceIpAddress = $Using:TargetDeviceIpAddress
        $StorageAccountName = $Using:StorageAccountName
        $StorageAccountKey = $Using:StorageAccountKey
        $VMGUIDS = $Using:VMGUIDS
        $ScriptContainer = $Using:ScriptContainer
        $ScriptPSFileName = $Using:ScriptPSFileName
        $RecoveryPlanContext = $Using:RecoveryPlanContext
        $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT

        $BackupPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/backups/"
        $BackupPolicyPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/backupPolicies/"
        $VolumeContainerPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/volumeContainers/"
        
        # Set Current directory path
        $ScriptDirectory = "C:\Modules\User\Microsoft.Azure.Management.StorSimple8000Series"

        # Load all StorSimple8000Series & dependent dlls
        [Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.IdentityModel.Clients.ActiveDirectory.dll")) | Out-Null
        [Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.dll")) | Out-Null
        [Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.dll")) | Out-Null
        [Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Newtonsoft.Json.dll")) | Out-Null
        [Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.Authentication.dll")) | Out-Null
        [Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Azure.Management.Storsimple8000series.dll")) | Out-Null

        $SyncContext = New-Object System.Threading.SynchronizationContext
        [System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

        $BaseUri = New-Object System.Uri -ArgumentList $BaseUrl
        
        # Instantiate clientAssertionCertificate
        $clientAssertionCertificate = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientAssertionCertificate -ArgumentList $ClientId, $ClientCertificate

        # Verify Credentials
        Write-Output "Connecting to Azure"
        $Credentials = [Microsoft.Rest.Azure.Authentication.ApplicationTokenProvider]::LoginSilentWithCertificateAsync($TenantId, $clientAssertionCertificate).GetAwaiter().GetResult()
        if ($Credentials -eq $null) {
             throw "Failed to authenticate!"
        }

        try {
            $StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $BaseUri, $Credentials
        
            # Sleep before connecting to Azure account (PowerShell)
            Start-Sleep -s $SLEEPTIMEOUT
        } catch {
            Write-Error -Message $_.Exception
            throw $_.Exception
        }

        # Login into Azure account for Azure PowerShell CmdLets
        If ($StorSimpleClient -ne $null)
        {
            $AzureRmAccount = Add-AzureRmAccount `
                                -ServicePrincipal `
                                -TenantId $using:ServicePrincipalConnection.TenantId `
                                -ApplicationId $using:ServicePrincipalConnection.ApplicationId `
                                -CertificateThumbprint $using:ServicePrincipalConnection.CertificateThumbprint
        }

        # Set SubscriptionId
        $StorSimpleClient.SubscriptionId = $SubscriptionId

        try {
            $Device = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::Get($StorSimpleClient.Devices, $DeviceName, $ResourceGroupName, $ManagerName)
            $TargetDevice = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::Get($StorSimpleClient.Devices, $TargetDeviceName, $ResourceGroupName, $ManagerName)
        } catch {
            throw $_.Exception
        }
        
        if (($Device -eq $null) -or ($Device.Status -ne "Online")) {
            throw "Device $DeviceName does not exist or is not online"
        }
        
        if (($TargetDevice -eq $null) -or ($TargetDevice.Status -ne "Online")) {
            throw "Target device $TargetDeviceName does not exist or is not online"
        }

        $DeviceIQN = ($Device).TargetIQN
        if ([string]::IsNullOrEmpty($DeviceIQN)) {
            throw "IQN for $DeviceName is null"
        }

        $TargetDeviceIQN = $TargetDevice.TargetIQN
        if ([string]::IsNullOrEmpty($TargetDeviceIQN)) {
            throw "IQN for $TargetDeviceName is null"
        }

        $TargetVM = Get-AzureRmVM -Name $TargetDeviceName -ResourceGroupName $ResourceGroupName 
        if ($TargetVM -eq $null) {
            throw "TargetDeviceName or ResourceGroupName asset is incorrect"
        }

        $FailoverType = $RecoveryPlanContext.FailoverType

        $IPAddress = $TargetDeviceIpAddress
        if ([string]::IsNullOrEmpty($IPAddress)) {
            throw "IP Address of $TargetDeviceName is null"
        }

        foreach ($VMGUID in $VMGUIDS)
        {
            # Fetch VM Details
            $VMContext = $RecoveryPlanContext.VmMap.$VMGUID
            if ($VMContext -eq $null) {
                throw "The VM corresponding to the VMGUID - $VMGUID is not included in the Recovery Plan"
            }
            
            $VMRoleName =  $VMContext.RoleName 
            if ($VMRoleName -eq $null) {
                throw "Role name is null for VMGUID - $VMGUID"
            }
            
            $VMServiceName = $VMContext.ResourceGroupName
            if ($VMServiceName -eq $null) {
                throw "Resource group name is null for VMGUID - $VMGUID"
            }
        
            Write-Output "`nVM Name: $VMRoleName"

            # Replace actual Virtual machine name
            $ScriptName = $ScriptPSFileName -Replace "VMName-Timestamp", ($VMRoleName + '-' + (Get-Date).ToString("MMddyyyy-hhmmsss"))
       
            $Context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
            if ($Context -eq $null) {
                throw "Invalid StorageAccountName or StorageAccountKey"
            }
       
            # Check if the Container already exists; if not, create it
            $Container =  Get-AzureStorageContainer -Name $ScriptContainer -Context $Context -ErrorAction:SilentlyContinue
            if ($Container -eq $null) {
                Write-Output "Creating container $ScriptContainer"
                try {
                     $Container = New-AzureStorageContainer -Name $ScriptContainer -Context $Context
                } catch {
                    throw "Unable to create container $ScriptContainer"
                }
            }

            $text = "
            If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] `"Administrator`"))
             {   
             `$arguments = `"& '`" + `$myinvocation.mycommand.definition + `"' `"  
             Start-Process `"`$psHome\powershell.exe`" -Verb runAs -ArgumentList '-noexit',`$arguments
             break
             }
             Disconnect-IscsiTarget -NodeAddress $DeviceIQN -Confirm:`$false
             `$portal = Get-IscsiTargetPortal -TargetPortalAddress $IPAddress
             if (`$portal -eq `$null)
             {
                 New-IscsiTargetPortal -TargetPortalAddress $IPAddress
             }
             Connect-IscsiTarget -NodeAddress $TargetDeviceIQN -IsPersistent `$true
             Update-StorageProviderCache
             Update-HostStorageCache 
             Get-Disk  | Where-Object {`$_.Model -match 'STORSIMPLE*'}  | Set-Disk -IsOffline `$false
             Get-Disk  | Where-Object {`$_.Model -match 'STORSIMPLE*'}  | Set-Disk -IsReadOnly `$false"
        
            $ScriptFileName = ('C:\iscsi-' + $VMRoleName + '.ps1')
            $text | Set-Content $ScriptFileName
        
            Write-Output "Writing file '$ScriptName' to '$ScriptContainer'"
            $uri = Set-AzureStorageBlobContent -Blob $ScriptName -Container $ScriptContainer -File $ScriptFileName -Context $Context -Force
            if ($uri -eq $null) {
                throw "Unable to write file $ScriptName to container $ScriptContainer"
            }

            # Create a URI for the file in the container 
            $sasuri = New-AzureStorageBlobSASToken -Container $ScriptContainer -Blob $ScriptName -Permission r -FullUri -Context $Context 
            if ($sasuri -eq $null) {
                throw "Unable to fetch URI for the file $ScriptName"
            }
        
            $AzureVM = Get-AzureRmVM -Name $VMRoleName -ResourceGroupName $VMServiceName        
            if ($AzureVM -eq $null) {
                throw "Unable to connect to Azure VM $VMRoleName"
            }
            
            Write-Output "Running script on the VM on $VMRoleName"
            try {
                 $result = Set-AzureRmVMCustomScriptExtension -ResourceGroupName $VMServiceName -VMName $VMRoleName -Location $AzureVM.Location -Name "CustomScriptExtension" -TypeHandlerVersion "1.1" -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -FileName $ScriptName -ContainerName $ScriptContainer
            } catch {
                 throw "Unable to run the script on the VM - $VMRoleName"
            }    

            while ($true)
            {
                $AzureVM = Get-AzureRmVM -ResourceGroupName $VMServiceName -Name $VMRoleName
                if ($AzureVM -eq $null) {
                    throw "Unable to connect to Azure VM"
                }

                #Check if the status is finished execution
                $extension = $AzureVM.Extensions | Where-Object {$_.VirtualMachineExtensionType -eq "CustomScriptExtension"}
                if ($AzureVM.Extensions -eq $null -or $AzureVM.Extensions.Count -eq 0 -or $extension -eq $null) {
                    continue
                } elseIf ($extension.ProvisioningState -eq 'Succeeded') {
                    break
                }
	 		   
                Start-Sleep -s $SLEEPTIMEOUT
            }
            Write-Output "Completed running script on VM - $VMRoleName"
        }
    }
}
