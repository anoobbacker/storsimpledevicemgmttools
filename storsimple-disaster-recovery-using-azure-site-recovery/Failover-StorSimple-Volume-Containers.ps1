<#
.DESCRIPTION
    This runbook performs a failover of the StorSimple volume containers corresponding to the particular Azure Site Recovery failover.
    Unplanned failover - The specified volume containers are failed over to the target Device
    Planned failover - Backups of all the volumes in the volume containers are taken based on the backup policies which were last used to take a successful backup and then the volume containers are failed over on to the Target Device
    Test failover - All the volumes in the volume containers are cloned on to the target Device
    Failback - It performs the same steps as in the case of a planned failover with the Source Device and Target Device swapped
     
.ASSETS 
    [You can choose to encrypt these assets ]

    The following have to be added with the Recovery Plan Name as a prefix, eg - TestPlan-StorSimRegKey [where TestPlan is the name of the recovery plan]
    [All these are String variables]
    
    BaseUrl: The resource manager url of the Azure cloud. Get using "Get-AzureRmEnvironment | Select-Object Name, ResourceManagerUrl" cmdlet.
    'RecoveryPlanName'-ResourceGroupName: The name of the resource group on which to read storsimple virtual appliance info
    'RecoveryPlanName'-ResourceName: The name of the StorSimple resource
    'RecoveryPlanName'-DeviceName: The Device which has to be failed over
    'RecoveryPlanName'-TargetDeviceName: The Device on which the containers are to be failed over
    'RecoveryPlanName'-VolumeContainers: A comma separated string of volume containers present on the Device that need to be failed over, eg - "VolCon1,VolCon2"
    
.NOTES
    If a specified container can't be failed over then it'll be ignored
    If a volume container is part of a group (in case of shared backup policies) then the entire group will be failed over if even one of the containers from the group is not specified
#>
workflow Failover-StorSimple-Volume-Containers
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
    
    $ContainerNames = Get-AutomationVariable -Name "$PlanName-VolumeContainers"
    if ($ContainerNames -eq $null)
    { 
        throw "The VolumeContainers asset has not been created in the Automation service."  
    }
    $VolumeContainers =  $ContainerNames.Split(",").Trim()
     
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
    
    $BackupType = "CloudSnapshot"
    $SLEEPTIMEOUT = 20 # Value in seconds
    $CurrentTime = Get-Date

    InlineScript 
    {
        $BaseUrl = $Using:BaseUrl
        $SubscriptionId = $Using:SubscriptionId
        $TenantId = $Using:TenantId
        $ClientId = $Using:ClientId
        $ClientCertificate = $Using:ClientCertificate
        $DeviceName = $Using:DeviceName
        $TargetDeviceName = $Using:TargetDeviceName
        $VolumeContainers = $Using:VolumeContainers
        $ResourceGroupName = $Using:ResourceGroupName
        $ManagerName = $Using:ManagerName
        $BackupType = $Using:BackupType
        $RecoveryPlanContext = $Using:RecoveryPlanContext
        $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT
        $CurrentTime = $Using:CurrentTime

        $BackupPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/backups/"
        $BackupPolicyPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/backupPolicies/"
        $VolumeContainerPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/volumeContainers/"

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
            $StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $BaseUri, $Credentials
        
            # Sleep before connecting to Azure account (PowerShell)
            Start-Sleep -s $SLEEPTIMEOUT
        } catch {
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
        
        If ($StorSimpleClient -eq $null -or $StorSimpleClient.GenerateClientRequestId -eq $false) {
            throw "Unable to connect Azure"
        }
        
        # Set SubscriptionId
        $StorSimpleClient.SubscriptionId = $SubscriptionId
        
        # Swap in case of a failback
        if ($RecoveryPlanContext.FailoverType -eq "Failback") {
            $DeviceName,$TargetDeviceName = $TargetDeviceName,$DeviceName  
        }

        try {
            # Fetch Source StorSimple Device details
            $Device = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::Get($StorSimpleClient.Devices, $DeviceName, $ResourceGroupName, $ManagerName)
        } catch {
            throw $_.Exception
        }

        try {
            # Fetch Target StorSimple Device details
            $TargetDevice = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::Get($StorSimpleClient.Devices, $TargetDeviceName, $ResourceGroupName, $ManagerName)
        } catch {
            throw $_.Exception
        }
        
        if ($Device -eq $null) {
            throw "Device ($DeviceName) does not exist"
        } elseIf ($Device.Status -ne "Online") {
            throw "Device ($DeviceName) is $($Device.Status)"
        }
        
        if ($TargetDevice -eq $null) {
            throw "Target device ($TargetDeviceName) does not exist"
        } elseIf ($TargetDevice.Status -ne "Online") {
            throw "Target device ($TargetDeviceName) is $($TargetDevice.Status)"
        }
    
        try {
            # Get all volume container groups from a Device which are eligible for failover
            $eligibleContainers = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::ListFailoverSets($StorSimpleClient.Devices, $DeviceName, $ResourceGroupName, $ManagerName)

            # Retrieve only eligible volume container(s) for failover
            $eligibleContainers = ($eligibleContainers | Where-Object {$_.EligibilityResult.IsEligibleForFailover})
        } catch {
            throw $_.Exception
        }
        
        if ($eligibleContainers -eq $null) {
            throw "No volume containers exist on the Device that can be failed over"
        }       
        
        # ContainerNamesArray - stores the ContainerNames of the volume containers for comparison
        $ContainerNamesArray = @()
        $eligibleContainers | %{ $_.VolumeContainers.VolumeContainerId.Split(',') | % { $ContainerNamesArray += (, $_.SubString($_.LastIndexOf('/')+1)) } }

        # ChosenVolContainers - volume containers that are eligible to be failed over from the ones enters by the user 
        $chosenVolContainers = @()

        # Find the common containers between the ones entered by the user and the ones those are eligible for a failover
        # If a volume container belongs to a group, then all the volume containers in that group will be failed over (in case of a shared backup poilcy)
        foreach ($VolCont in $VolumeContainers) {
            foreach($eligibleVolCont in $eligibleContainers) {
                $eligibleVolCont.VolumeContainers.VolumeContainerId.Split(',') | % {
                    if ($_.Contains($VolCont)) {
                        $chosenVolContainers += $eligibleVolCont
                     }
                 }
            }
        }

        # Remove duplicate entries
        $chosenVolContainers = $chosenVolContainers | select -Unique

        if ($chosenVolContainers -eq $null -or $chosenVolContainers.Length -eq 0) {
           throw "No Volume containers among the specified ones are eligible for failover"
        }

        # Fetch unique backup policy id(s)
        $BackupPolicies = $chosenVolContainers | Select -ExpandProperty VolumeContainers | select -ExpandProperty Volumes | select BackupPolicyId -Unique

        if ($BackupPolicies -eq $null -or $BackupPolicies.Length -eq 0) {
            throw "No backup policies were found"
        }
        
        # Retrieves all the backups in a device
        $Backups = @()
        try {
            foreach ($BackupPolicy in $BackupPolicies | Select BackupPolicyId) {
                $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.BackupFilter] -ArgumentList "BackupPolicyId eq '$($BackupPolicy.BackupPolicyId)'"
                $Backups += [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::ListByDevice($StorSimpleClient.Backups, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
            }
        } catch {
            throw $_.Exception
        }

        # Filter otherthan CloudSnapshot backuptypes
        $Backups = $Backups | where BackupType -eq $BackupType
        
        if ($Backups -eq $null -or $Backups.Count -eq 0) {
            throw "No backup exists"
        }
        
        if (($RecoveryPlanContext.FailoverType -eq "Planned") -or ($RecoveryPlanContext.FailoverType -eq "Failback")) 
        {
            # Set Current time
            $CurrentTime = Get-Date
            $countOfTriggeredBackups = 0

            Write-Output "Backup(s) initiated"
            # Trigger manual cloudsnapshot
            foreach ($BackupPolicy in $BackupPolicies | Select BackupPolicyId)
            {
                $BackupPolicyName = $BackupPolicy.BackupPolicyId.SubString($BackupPolicy.BackupPolicyId.LastIndexOf('/') + 1)
                try {
                    # Trigger manual backup job
                    $BackupResult = [Microsoft.Azure.Management.StorSimple8000Series.BackupPoliciesOperationsExtensions]::BackupNowAsync($StorSimpleClient.BackupPolicies, $DeviceName, $BackupPolicyName, $BackupType, $ResourceGroupName, $ManagerName)
                    if ($BackupResult -ne $null -and $BackupResult.IsFaulted) {
                        throw $BackupResult.Exception
                    }

                    # Sleep before reading job list
                    Start-Sleep -s $SLEEPTIMEOUT
                } catch {
                    throw $_.Exception
                }

                $countOfTriggeredBackups += 1
                $BackupPolicNames += $BackupPolicyName
            }

            Write-Output "Fetching backup job list"
            $jobIDs = $null
            $TotalTimeoutPeriod = 0
            while ($true)
            {
                try {
                    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.JobFilter] -ArgumentList "starttime ge '$($CurrentTime.ToString('r'))' and jobtype eq 'ManualBackup'"
                    $jobList = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
                } catch {
                    throw $_.Exception
                }

                if ($jobList -eq $null -or $jobList.Length -eq 0) {
                    throw "Unable to get the backup jobs"
                }

                try {
                    # Filter other jobs by EntityLabel (BackupPolicyName)
                    $jobsListArray = @()
                    foreach ($jobData in $jobList) {
                        if (($BackupPolicNames -eq $jobData.EntityLabel) -ne $null) {
                            $jobsListArray += $jobData
                        }
                    }

                    # Filter the job list & read job names/ids
                    $jobIDs = ($jobsListArray | Where-Object {$_.JobType -eq 'ManualBackup' -and $_.Id -Like '*' + $DeviceName + '*' -and $_.StartTime -ge $CurrentTime} | sort StartTime -Descending).Name

                    $jobIDsReady = $true
                    foreach ($jobID in $jobIDs) {
                        if ($jobID -eq $null) {
                            $jobIDsReady = $false
                            break
                        }
                    }
                    
                    $TotalTimeoutPeriod += $SLEEPTIMEOUT
                    if ($TotalTimeoutPeriod -gt 300) { #5 minutes
                        throw "Unable to fetch backup job list"
                    }

                    if ($jobIDsReady -ne $true) {
                        continue
                    }
                    
                    if ($jobIDs.Count -eq $countOfTriggeredBackups) {
                        break
                    }
                } catch {
                    throw $_.Exception
                }
            }
            
            Write-Output "Waiting for backups to finish"
            $checkForSuccess=$true
            foreach ($id in $jobIDs)
            {
                while ($true)
                {
                    Start-Sleep -s $SLEEPTIMEOUT
                    try {
                        $status = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::Get($StorSimpleClient.Jobs, $DeviceName, $id, $ResourceGroupName, $ManagerName)
                    } catch {
                        throw $_.Exception
                    }

                    if ($status.Status -ne "Running") {
                        if ($status.Status -ne "Succeeded") {
                            $checkForSuccess=$false
                        }
                        break
                    }
                }
            }
            if ($checkForSuccess) {
                Write-Output ("Backups completed successfully")
            }
            else {
                throw "Backups unsuccessful"
            }
        }

        if ($RecoveryPlanContext.FailoverType -ne "Test")
        {
            # Set Current time
            $CurrentTime = Get-Date

            $chosenVolumeContainersList = New-Object System.Collections.Generic.List[System.String]
            $chosenVolContainers.VolumeContainers.VolumeContainerId | % { $chosenVolumeContainersList.Add($_)}
            Write-Output "Initiating failover operation for the chosen volume containers"
            Write-Output "  Source device name: $DeviceName"
            Write-Output "  Target device name: $TargetDeviceName"
            
            $VolContainers = ($chosenVolumeContainersList | select -ExpandProperty VolumeContainers | select VolumeContainerId).VolumeContainerId.Replace($VolumeContainerPath, "") -Join ","
            Write-Output "  Volume containers: $($VolContainers)"
            
            $failoverRequest = New-Object Microsoft.Azure.Management.StorSimple8000Series.Models.FailoverRequest -ArgumentList $TargetDevice.Id, $chosenVolumeContainersList

            try {
                $FailoverResult = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::FailoverAsync($StorSimpleClient.Devices, $DeviceName, $failoverRequest, $ResourceGroupName, $ManagerName)
                if ($FailoverResult -ne $null -and $FailoverResult.IsFaulted) {
                    throw $FailoverResult.Exception
                }
            } catch {
                throw $_.Exception
            }

            Start-Sleep -s $SLEEPTIMEOUT
            Write-Output "Fetching failover job"
            try {
                $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.JobFilter] -ArgumentList "starttime ge '$($CurrentTime.ToString('r'))' and jobtype eq 'FailoverVolumeContainers'"
                $jobList = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $TargetDeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
            } catch {
                throw $_.Exception
            }

            # Filter the job list & read job names/ids
            $jobData = ($jobList | Where-Object {$_.JobType -eq 'FailoverVolumeContainers' -and $_.StartTime -ge $CurrentTime} | sort StartTime -Descending)
            
            if ($jobData -eq $null) {
                throw "Failover couldn't be initiated on $DeviceName"
            }
            elseIf ($jobData.Count -gt 1) {
                $jobID = $jobData[0].Name
            }
            else {
                $jobID = $jobData.Name
            }

            Write-Output "Failover initiated"
            Write-Output "Waiting for failover to complete"
            # Waiting for failover job to finish"
            $checkForSuccess=$true
            while ($true)
            {
                Start-Sleep -s $SLEEPTIMEOUT
                try {
                    $status = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::Get($StorSimpleClient.Jobs, $TargetDeviceName, $jobID, $ResourceGroupName, $ManagerName)
                } catch {
                    throw $_.Exception
                }

                if ($status.Status -ne "Running" ) {
                    if ($status.Status -ne "Succeeded") {
                        $checkForSuccess=$false
                    }
                    break
                }
            }
            if ($checkForSuccess) {
                Write-Output ("Failover completed successfully")
            } else {
                throw ("Failover unsuccessful")
            }
        }
        else
        {
            # Clone all the volumes in the volume containers as per the latest backup                         
            if (($chosenVolContainers | select -ExpandProperty VolumeContainers | select -ExpandProperty Volumes | select -First 1).Count -eq 0) {
                throw "No volumes in the containers"
            }
            
            Write-Output "Initiating clone operation for the chosen volume containers"
            Write-Output "  Source device name: $DeviceName"
            Write-Output "  Target device name: $TargetDeviceName"
            $CloneStartTime = Get-Date
            $countOfTriggeredClones = 0
            foreach ($vol in ($chosenVolContainers | select -ExpandProperty VolumeContainers | select -ExpandProperty Volumes))
            {
                $BackupName = $vol.BackupId.Replace($BackupPath, "")
                $BackupPolicyName = $vol.BackupPolicyId.Replace($BackupPolicyPath, "")
                $BackupData = $Backups | where-object {$_.Id -eq $vol.BackupId}
                $BackupElementName = $vol.BackupElementId.SubString($vol.BackupElementId.LastIndexOf("/") + 1)
                $VolumeContainerName = $vol.VolumeId.Replace($VolumeContainerPath, "")
                $VolumeContainerName = $VolumeContainerName.SubString(0, $VolumeContainerName.IndexOf("/"))
                $VolumeName = $vol.VolumeId.SubString($vol.VolumeId.LastIndexOf("/") + 1)

                # Fetch the ACR List
                try {
                    $Volumes = [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::ListByVolumeContainer($StorSimpleClient.Volumes, $DeviceName, $VolumeContainerName, $ResourceGroupName, $ManagerName)
                    
                    if ($Volumes -ne $null -and $Volumes.IsFaulted) {
                        throw $Volumes.Exception
                    }
                } catch {
                    throw $_.Exception
                }

                $VolumeData = ($Volumes | where Name -eq $VolumeName)
                $BackupElement = $BackupData.Elements | where-object {$_.VolumeName -eq $VolumeData.Name}

                $AccessControlRecordIds = New-Object System.Collections.Generic.List[System.String]
                $VolumeData.AccessControlRecordIds | % { $AccessControlRecordIds.Add($_) }

                Write-Output "  Clone volume name: $($VolumeData.Name)"
                $CloneRequest = New-Object Microsoft.Azure.Management.StorSimple8000Series.Models.CloneRequest -ArgumentList $TargetDevice.Id, $VolumeData.Name, $AccessControlRecordIds, $BackupElement
                try {
                    $CloneResult = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::CloneAsync($StorSimpleClient.Backups, $DeviceName, $BackupName, $BackupElementName, $CloneRequest, $ResourceGroupName, $ManagerName)
                    if ($CloneResult -ne $null -and $CloneResult.IsFaulted) {
                        throw $CloneResult.Exception
                    }
                    
                    Start-Sleep -s $SLEEPTIMEOUT
                } catch {
                    throw $_.Exception
                }

                # Increament clone job count
                $countOfTriggeredClones += 1
            }            

            Write-Output "Fetching clone job list"
            $jobIDs = $null
            $TotalTimeoutPeriod = 0
            while ($true)
            {
                Start-Sleep -s $SLEEPTIMEOUT
                try {
                    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.JobFilter] -ArgumentList "starttime ge '$($CloneStartTime.ToString('r'))' and jobtype eq 'CloneVolume'"
                    $jobList = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $TargetDeviceName, $ResourceGroupName, $ManagerName)
                } catch {
                    throw $_.Exception
                }

                if ($jobList -eq $null -or $jobList.Length -eq 0) {
                    throw "Unable to get the jobs"
                }

                try {
                    # Filter the job list & read job names/ids
                    $jobIDs = ($jobList | Where-Object {$_.JobType -eq 'CloneVolume' -and $_.StartTime -ge $CloneStartTime} | sort StartTime -Descending).Name

                    $jobIDsReady = $true
                    foreach ($jobID in $jobIDs) {
                        if ($jobID -eq $null) {
                            $jobIDsReady = $false
                            break
                        }
                    }
                    
                    $TotalTimeoutPeriod += $SLEEPTIMEOUT
                    if ($TotalTimeoutPeriod -gt 300) { #5 minutes
                        $jobList | Sort StartTime -Descending | Select-Object Name, Status, JobType
                        throw "Unable to fetch the clone job list"
                    }

                    if ($jobIDsReady -ne $true) {
                        continue
                    }
                    
                    if ($jobIDs.Count -eq $countOfTriggeredClones) {
                        break
                    }
                } catch {
                    throw $_.Exception
                }
            }
            
            Write-Output "Waiting for clone job to complete"
            $checkForSuccess=$true
            foreach ($JobName in $jobIDs)
            {
                while ($true)
                {
                    try {
                        $cloneJobData = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::Get($StorSimpleClient.Jobs, $TargetDeviceName, $JobName, $ResourceGroupName, $ManagerName)
                    } catch {
                        throw $_.Exception
                    }

                    if ($cloneJobData.Status -ne "Running") {
                        if ($cloneJobData.Status -ne "Succeeded") {
                            $checkForSuccess=$false
                        }
                        break
                    }
                    # Waiting for clone job(s) to complete
                    Start-Sleep -s $SLEEPTIMEOUT
                }
            }
            if ($checkForSuccess) {
                Write-Output ("Clone(s) completed successfully")
            }
            else {
                throw "Clone unsuccessful"
            }
        }

        If ($StorSimpleClient -ne $null -and $StorSimpleClient -is [System.IDisposable]) {
            $StorSimpleClient.Dispose()
        }
    }
}