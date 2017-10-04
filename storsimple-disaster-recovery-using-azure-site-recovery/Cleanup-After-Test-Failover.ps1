<#
.DESCRIPTION
    This runbook acts as a cleanup script for the Test Failover scenario
    This runbook deletes all the volumes, backups, backup policies and volume contaienrs on the target device.
    This runbook also shuts down the SVA after the manual action in case of a Test Failover
    
.ASSETS (The following need to be stored as Automation Assets)
    [You can choose to encrypt these assets ]

    The following have to be added with the Recovery Plan Name as a prefix, eg - TestPlan-StorSimRegKey [where TestPlan is the name of the recovery plan]
    [All these are String variables]

    BaseUrl: The resource manager url of the Azure cloud. Get using "Get-AzureRmEnvironment | Select-Object Name, ResourceManagerUrl" cmdlet.
    'RecoveryPlanName'-ResourceGroupName: The name of the resource group on which to read storsimple virtual appliance info
    'RecoveryPlanName'-ResourceName: The name of the StorSimple resource
    'RecoveryPlanName'-TargetDeviceName: The device on which the test failover was performed (the one which needs to be cleaned up)
#>

workflow Cleanup-After-Test-Failover
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
     
    $TargetDeviceName = Get-AutomationVariable -Name "$PlanName-TargetDeviceName"
    if ($TargetDeviceName -eq $null) 
    { 
        throw "The TargetDeviceName asset has not been created in the Automation service."  
    }
     
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

    $SLEEPTIMEOUT = 10    # Value in seconds
    $SLEEPLARGETIMEOUT = 300    # Value in seconds

    InlineScript
    {
        $BaseUrl = $Using:BaseUrl
        $SubscriptionId = $Using:SubscriptionId
        $TenantId = $Using:TenantId
        $ClientId = $Using:ClientId
        $ClientCertificate = $Using:ClientCertificate
        $TargetDeviceName = $Using:TargetDeviceName
        $ResourceGroupName = $Using:ResourceGroupName
        $ManagerName = $Using:ManagerName
        $RecoveryPlanContext = $Using:RecoveryPlanContext
        $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT
        $SLEEPLARGETIMEOUT = $Using:SLEEPLARGETIMEOUT

        if ($RecoveryPlanContext.FailoverType -eq "Test")
        {
            # Set Current directory path
            $ScriptDirectory = "C:\Modules\User\Microsoft.Azure.Management.StorSimple8000Series"
            #ls $ScriptDirectory

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
                throw "Unable to connect Azure"
            }

            try {
                # Instantiate StorSimple8000SeriesClient
                $StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $BaseUri, $Credentials
            
                # Sleep before connecting to Azure account (PowerShell)
                Start-Sleep -s $SLEEPTIMEOUT
            } catch {
                Write-Error -Message $_.Exception
                throw $_.Exception
            }

            # Login into Azure account for PowerShell CmdLets
            If ($StorSimpleClient -ne $null)
            {
                $AzureRmAccount = Add-AzureRmAccount `
                                    -ServicePrincipal `
                                    -TenantId $using:ServicePrincipalConnection.TenantId `
                                    -ApplicationId $using:ServicePrincipalConnection.ApplicationId `
                                    -CertificateThumbprint $using:ServicePrincipalConnection.CertificateThumbprint
            }
            
            If ($StorSimpleClient -eq $null -or $StorSimpleClient.GenerateClientRequestId -eq $false -or $AzureRmAccount -eq $null) {
                throw "Unable to connect Azure"
            }
            
            # Set SubscriptionId
            $StorSimpleClient.SubscriptionId = $SubscriptionId

            try {
                # Fetch Target StorSimple Device details
                $TargetDevice = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::Get($StorSimpleClient.Devices, $TargetDeviceName, $ResourceGroupName, $ManagerName)
            } catch {
                throw $_.Exception
            }
            
            if ($TargetDevice -eq $null) {
                throw "Target device ($TargetDeviceName) does not exist"
            } elseIf ($TargetDevice.Status -ne "Online") {
                throw "Target device ($TargetDeviceName) is $($TargetDevice.Status)"
            }
                
            Write-Output "Initiating cleanup of volumes and volume containers"
            try 
            {
                $VolumeContainers = [Microsoft.Azure.Management.StorSimple8000Series.VolumeContainersOperationsExtensions]::ListByDevice($StorSimpleClient.VolumeContainers, $TargetDeviceName, $ResourceGroupName, $ManagerName)
                if ($VolumeContainers -ne $null)
                {
                    foreach ($Container in $VolumeContainers) 
                    {
                        $Volumes = [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::ListByVolumeContainer($StorSimpleClient.Volumes, $TargetDeviceName, $Container.Name, $ResourceGroupName, $ManagerName)
                        if ($Volumes -ne $null) 
                        {
                            foreach ($Volume in $Volumes) 
                            {
                                $RetryCount = 0
                                while ($RetryCount -lt 2)
                                {
                                    $isSuccessful = $true
                                    $VolumeStatus = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeStatus]::Offline
                                    $Volume.VolumeStatus = $VolumeStatus

                                    # Set Volume status "Offline"
                                    $VolumeResult = [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::CreateOrUpdate($StorSimpleClient.Volumes, $TargetDeviceName, $Container.Name, $Volume.Name, $Volume, $ResourceGroupName, $ManagerName)
                                    if ($VolumeResult -eq $null -or $VolumeResult.VolumeStatus -ne $VolumeStatus) {
                                        Write-Output "Volume - $($Volume.Name) could not be taken offline"
                                        $isSuccessful = $false
                                    } else {
                                        # Delete volume
                                        [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::Delete($StorSimpleClient.Volumes, $TargetDeviceName, $Container.Name, $Volume.Name, $ResourceGroupName, $ManagerName)
                                    }
                                    
                                    # Check whether volume available or not
                                    try {
                                        $VolumeData = [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::Get($StorSimpleClient.Volumes, $TargetDeviceName, $Container.Name, $Volume.Name, $ResourceGroupName, $ManagerName)
                                        $isSuccessful = $false
                                    }
                                    catch {
                                        $isSuccessful = $true
                                    }
                                    if ($isSuccessful) {
                                        Write-Output "Volume - $($Volume.Name) deleted"
                                        break
                                    }
                                    else {
                                        if ($RetryCount -eq 0) {
                                            Write-Output "Retrying for volumes deletion"
                                        } else {
                                            throw "Unable to delete Volume - $($Volume.Name)"
                                        }
                                                        
                                        Start-Sleep -s $SLEEPTIMEOUT
                                        $RetryCount += 1
                                    }
                                }
                            }
                        }
                    }
                    
                    Start-Sleep -s $SLEEPLARGETIMEOUT
                    Write-Output "Deleting Volume Containers"
                    foreach ($Container in $VolumeContainers) 
                    {
                        $RetryCount = 0 
                        while ($RetryCount -lt 2)
                        {
                            # Delete volume container
                            [Microsoft.Azure.Management.StorSimple8000Series.VolumeContainersOperationsExtensions]::Delete($StorSimpleClient.VolumeContainers, $TargetDeviceName, $Container.Name, $ResourceGroupName, $ManagerName)
                            
                            # Check whether volume container available or not
                            try {
                                [Microsoft.Azure.Management.StorSimple8000Series.VolumeContainersOperationsExtensions]::Get($StorSimpleClient.VolumeContainers, $TargetDeviceName, $Container.Name, $ResourceGroupName, $ManagerName)
                                $isSuccessful = $false
                            } catch {
                                $isSuccessful = $true
                            }
                            if ($isSuccessful) {
                                Write-Output "Volume Container - $($Container.Name) deleted"
                                break
                            }
                            else {
                                if ($RetryCount -eq 0) {
                                    Write-Output "Retrying for volume container deletion"
                                } else {
                                    Write-Output "Unable to delete Volume Container - $($Container.Name)"
                                }
                                                
                                Start-Sleep -s $SLEEPTIMEOUT
                                $RetryCount += 1   
                            }
                        }
                    }
                }
            } catch {
                throw $_.Exception
            }
            
            Write-Output "Cleanup completed" 
            Write-Output "Attempting to shutdown the SVA"
            if ($TargetDevice -ne $null -and $TargetDevice.Status -eq "Offline") {
                Write-Output "SVA turned off"
            }
            else {
                $RetryCount = 0
                while ((($TargetDevice -eq $null) -or ($TargetDevice.Status -ne "Online")) -and $RetryCount -lt 2)
                {
                    try {
                        $Result = Stop-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $TargetDeviceName -Force
                    } catch {
                        Write-Output $_.Exception
                    }
                    if ($Result.OperationStatus -eq "Succeeded" -or $Result.Status -eq "Succeeded") {
                        Write-Output "SVA succcessfully turned off"   
                        break
                    } else {
                        if ($RetryCount -eq 0) {
                            Write-Output "Retrying for SVA shutdown"
                        } else {
                            Write-Output "Unable to stop the SVA VM"
                        }

                        Start-Sleep -s $SLEEPTIMEOUT
                        $RetryCount += 1   
                    }
                }
            }

            If ($StorSimpleClient -ne $null -and $StorSimpleClient -is [System.IDisposable]) {
                $StorSimpleClient.Dispose()
            }
        }
    }
}