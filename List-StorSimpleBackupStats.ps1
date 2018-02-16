<#
.DESCRIPTION
    This scipt gives StorSimple Backup stats on BackupStatus, Available backups count and Status of backup jobs.

    Steps to execute the script: 
    ----------------------------
    1.  Open powershell, create a new folder & change directory to the folder.
            mkdir C:\scripts\StorSimpleSDKTools
            cd C:\scripts\StorSimpleSDKTools
    
    2.  Download nuget CLI under the same folder in Step1.
        Various versions of nuget.exe are available on nuget.org/downloads. Each download link points directly to an .exe file, so be sure to right-click and save the file to your computer rather than running it from the browser. 
            wget https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -Out C:\scripts\StorSimpleSDKTools\nuget.exe
    
    3.  Download the dependent SDK
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Azure.Management.Storsimple8000series
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.IdentityModel.Clients.ActiveDirectory -Version 2.28.3
            C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Rest.ClientRuntime.Azure.Authentication -Version 2.2.9-preview
    
    4.  Download the script from script center. 
            wget https://raw.githubusercontent.com/anoobbacker/storsimpledevicemgmttools/master/List-StorSimpleBackupStats.ps1?raw=true -Out List-StorSimpleBackupStats.ps1
            .\List-StorSimpleBackupStats.ps1 -SubscriptionId [subid] -TenantId [tenantid] -ResourceGroupName [resource group] -ManagerName [device manager] -DeviceName [device name] -AuthNType [Type of auth] -AADAppId [AAD app Id] -AADAppAuthNKey [AAD App Auth Key]
     
     ----------------------------
.PARAMS 
    SubscriptionId: Input the Subscription ID where the StorSimple 8000 series device manager is deployed.
    TenantId: Input the Tenant ID of the subscription. Get Tenant ID using Get-AzureRmSubscription cmdlet or go to the documentation https://aka.ms/ss8000-script-tenantid.

    ResourceGroupName: Input the name of the resource group on which to read volumes, backup catalogs and jobs.
    ManagerName: Input the name of the resource (StorSimple device manager) on which to read volumes, backup catalogs and jobs.
    DeviceName: Input the name of the StorSimple device on which to read volumes, backup catalogs and jobs.

    FilterByStartTime: Input the start time of the backups and jobs to be filtered. Eg: (Get-Date -Date "2017-01-01 10:30")
    FilterByEndTime: Input the end time of the backups and jobs to be filtered. Eg: (Get-Date -Date "2017-01-01 10:30")
    
    AuthNType: Input if you want to go with username, AAD authentication key or certificate. Refer https://aka.ms/ss8000-script-sp. 
        Possible values: [UserNamePassword, AuthenticationKey, Certificate]

    AADAppId: Input application ID for which the service principal was set. Refer https://aka.ms/ss8000-script-sp.

    AADAppAuthNKey: Input application authentication key for which the AAD application. Refer https://aka.ms/ss8000-script-sp.

    AADAppAuthNCertPath: Input the service principal certificate for the AAD application. Refer https://aka.ms/ss8000-script-spcert.
    AADAppAuthNCertPassword: Input the service principal ceritifcate password for the AAD application. Refer https://aka.ms/ss8000-script-spcert.
#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Input the Subscription ID where the StorSimple 8000 series device manager is deployed.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Input the ID of the tenant of the subscription. Get using Get-AzureRmSubscription cmdlet.")]
    [String]
    $TenantId,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource group on which to read volumes, backup catalogs and jobs.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the StorSimple device manager on which to read volumes, backup catalogs and jobs.")]
    [String]
    $ManagerName,

    [parameter(Mandatory = $false, HelpMessage = "Input the name of the StorSimple device on which to retrieve volumes, backup catalogs and jobs.")]
    [String]
    $DeviceName,

    [parameter(Mandatory = $false, HelpMessage = "Input the start time of the backups and jobs to be filtered.")]
    [DateTime]
    $FilterByStartTime,

    [parameter(Mandatory = $false, HelpMessage = "Input the end time of the backups and jobs to be filtered.")]
    [DateTime]
    $FilterByEndTime,

    [parameter(Mandatory = $false, HelpMessage = "Input if you want to go with username, AAD authentication key or certificate. Refer https://aka.ms/ss8000-script-sp.")]
    [ValidateSet('UserNamePassword', 'AuthenticationKey', 'Certificate')]
    [String]
    $AuthNType = 'UserNamePassword',

    [parameter(Mandatory = $false, HelpMessage = "Input application ID for which the service principal was set. Refer https://aka.ms/ss8000-script-sp.")]
    [String]
    $AADAppId,

    [parameter(Mandatory = $false, HelpMessage = "Input application authentication key for which the AAD application. Refer https://aka.ms/ss8000-script-sp.")]
    [String]
    $AADAppAuthNKey,

    [parameter(Mandatory = $false, HelpMessage = "Input the service principal certificate for the AAD application.")]
    [String]
    $AADAppAuthNCertPath,

    [parameter(Mandatory = $false, HelpMessage = "Input the service principal ceritifcate password for the AAD application.")]
    [String]
    $AADAppAuthNCertPassword
)

# Validate FilterByStartTime and FilterByEndTime
if ($FilterByStartTime -eq $null -and $FilterByEndTime -ne $null) {
    Write-Error "FilterByStartTime can not be null or empty. Please enter a valid date"
    return
} elseIf ($FilterByStartTime -ne $null -and $FilterByEndTime -eq $null) {
    Write-Error "FilterByEndTime can not be null or empty. Please enter a valid date"
    return
} elseIf ($FilterByStartTime -gt $FilterByEndTime) {
    Write-Error "FilterByStartTime can not be greaterthan FilterByEndTime"
    return
}

# Set Current directory path
$ScriptDirectory = $PSScriptRoot

# Load all required assemblies
[System.Reflection.Assembly]::LoadFrom((Join-Path $ScriptDirectory "Microsoft.IdentityModel.Clients.ActiveDirectory.2.28.3\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory.dll")) | Out-Null
[System.Reflection.Assembly]::LoadFrom((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.3.3.7\lib\net452\Microsoft.Rest.ClientRuntime.Azure.dll")) | Out-Null
[System.Reflection.Assembly]::LoadFrom((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.2.3.8\lib\net452\Microsoft.Rest.ClientRuntime.dll")) | Out-Null
[System.Reflection.Assembly]::LoadFrom((Join-Path $ScriptDirectory "Newtonsoft.Json.6.0.8\lib\net45\Newtonsoft.Json.dll")) | Out-Null
[System.Reflection.Assembly]::LoadFrom((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.Authentication.2.2.9-preview\lib\net45\Microsoft.Rest.ClientRuntime.Azure.Authentication.dll")) | Out-Null
[System.Reflection.Assembly]::LoadFrom((Join-Path $ScriptDirectory "Microsoft.Azure.Management.Storsimple8000series.1.0.0\lib\net452\Microsoft.Azure.Management.Storsimple8000series.dll")) | Out-Null

# Print method
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

# Create a query filter
Function GenerateBackupQueryFilter() {
    param([string] $FilterByEntityId, [DateTime] $FilterByStartTime, [DateTime] $FilterByEndTime)
    $queryFilter = $null

    if ($FilterByStartTime -ne $null) {
        $queryFilter = "createdTime ge '$($FilterByStartTime.ToString('r'))'"
    }

    if ($FilterByEndTime -ne $null) {
        if (![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        $queryFilter += "createdTime le '$($FilterByEndTime.ToString('r'))'"
    }

    if (!([string]::IsNullOrEmpty($FilterByEntityId))) {
        if (![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        if ($FilterByEntityId -like "*/backupPolicies/*") {
            $queryFilter += "backupPolicyId eq '$($FilterByEntityId)'"
        } elseif ($FilterByEntityId -like "*/volumeContainers/*") {
            $queryFilter += "volumeId eq '$($FilterByEntityId)'"
        }
    }

    return $queryFilter
}

# Create a query filter
Function GenerateJobQueryFilter() {
    param([String] $JobType, [DateTime] $FilterByStartTime, [DateTime] $FilterByEndTime)
    $queryFilter = $null

    if (!([string]::IsNullOrEmpty($FilterByEntityId))) {
        $queryFilter = "jobType eq '$($JobType)' "
    }

    if ($FilterByStartTime -ne $null -and $FilterByStartTime -ne '') { 
        if (![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        $queryFilter += "startTime ge '$($FilterByStartTime)'"
    }

    if ($FilterByEndTime -ne $null -and $FilterByEndTime -ne '') {
        if (![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        $queryFilter += "startTime le '$($FilterByEndTime)'"
    }

    return $queryFilter
}

# Define constant variables (DO NOT CHANGE BELOW VALUES)
$FrontdoorUrl = "urn:ietf:wg:oauth:2.0:oob"
$TokenUrl = "https://management.azure.com"   # Run 'Get-AzureRmEnvironment | Select-Object Name, ResourceManagerUrl' cmdlet to get the Fairfax url.
$DomainId = "1950a258-227b-4e31-a9cf-717495945fc2"

try {
    $FrontdoorUri = New-Object System.Uri -ArgumentList $FrontdoorUrl
    $TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

    # Set Synchronization context
    $SyncContext = New-Object System.Threading.SynchronizationContext
    [System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

    # Verify Credentials
    if ("UserNamePassword".Equals($AuthNType)) {    
        # Username password
        $AADClient = [Microsoft.Rest.Azure.Authentication.ActiveDirectoryClientSettings]::UsePromptOnly($DomainId, $FrontdoorUri)
        $Credentials = [Microsoft.Rest.Azure.Authentication.UserTokenProvider]::LoginWithPromptAsync($TenantId, $AADClient).GetAwaiter().GetResult()
    } elseif ("AuthenticationKey".Equals($AuthNType) ) {
        # AAD Application authentication key
        if ([string]::IsNullOrEmpty($AADAppId) -or [string]::IsNullOrEmpty($AADAppAuthNKey)) {
            throw "Invalid inputs! Ensure that you input the arguments -AADAppId and -AADAppAuthNKey."
        }

        $Credentials =[Microsoft.Rest.Azure.Authentication.ApplicationTokenProvider]::LoginSilentAsync($TenantId, $AADAppId, $AADAppAuthNKey).GetAwaiter().GetResult();
    } elseif ("Certificate".Equals($AuthNType) ) {
        # AAD Service Principal Certificates
        if ([string]::IsNullOrEmpty($AADAppId) -or [string]::IsNullOrEmpty($AADAppAuthNCertPassword) -or [string]::IsNullOrEmpty($AADAppAuthNCertPath)) {
            throw "Invalid inputs! Ensure that you input the arguments -AADAppId, -AADAppAuthNCertPath and -AADAppAuthNCertPassword."
        }    
        if (!(Test-Path $AADAppAuthNCertPath)) {
            throw "Certificate file $AADAppAuthNCertPath couldn't found!"    
        }
        $CertPassword = ConvertTo-SecureString $AADAppAuthNCertPassword -AsPlainText -Force
        $ClientCertificate = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($AADAppAuthNCertPath, $CertPassword)
        
        $ClientAssertionCertificate = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientAssertionCertificate -ArgumentList $AADAppId, $ClientCertificate
        
        $Credentials = [Microsoft.Rest.Azure.Authentication.ApplicationTokenProvider]::LoginSilentWithCertificateAsync($TenantId, $ClientAssertionCertificate).GetAwaiter().GetResult()
    }

    if ($Credentials -eq $null) {
        throw "Failed to authenticate!"
    }

    # Get StorSimpleClient instance
    $StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $TokenUri, $Credentials

    # Set SubscriptionId
    $StorSimpleClient.SubscriptionId = $SubscriptionId


    # Fetch all Volumes at Device level
    $Volumes = [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::ListByDevice($StorSimpleClient.Volumes, $DeviceName, $ResourceGroupName, $ManagerName)


    # Fetch all 'Scheduled' backup jobs
    $JobType = [Microsoft.Azure.Management.StorSimple8000Series.Models.JobType]::ScheduledBackup
    $JobFilter = GenerateJobQueryFilter $JobType
    if ($FilterByStartTime -ne $null -and $FilterByEndTime -ne $null) {
        $JobFilter = GenerateJobQueryFilter $JobType $FilterByStartTime.ToString('r') $FilterByEndTime.ToString('r')
    }
    
    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.JobFilter] -ArgumentList $JobFilter
    $Jobs = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)


    # Fetch all 'Manual' backup jobs
    $JobType = [Microsoft.Azure.Management.StorSimple8000Series.Models.JobType]::ManualBackup
    $JobFilter = GenerateJobQueryFilter $JobType
    if ($FilterByStartTime -ne $null -and $FilterByEndTime -ne $null) {
        $JobFilter = GenerateJobQueryFilter $JobType $FilterByStartTime.ToString('r') $FilterByEndTime.ToString('r')
    }

    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.JobFilter] -ArgumentList $JobFilter
    $Jobs += [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)

    
    $VolumeContainerPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/volumeContainers/"
    $BackupPolicyPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.StorSimple/managers/$ManagerName/devices/$DeviceName/backupPolicies/"

    $VolumeStats = @()
    foreach($Volume in $Volumes)
    {
        # Fetch all Bakcups by Volume.Id
        $BackupFilter = GenerateBackupQueryFilter $Volume.Id
        if ($FilterByStartTime -ne $null -and $FilterByEndTime -ne $null) {
            $BackupFilter = GenerateBackupQueryFilter $Volume.Id $FilterByStartTime $FilterByEndTime
        }
        $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.BackupFilter] -ArgumentList $BackupFilter
        $Backups = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::ListByDevice($StorSimpleClient.Backups, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)


        # Fetch all Jobs by BackupPolicyName
        $VolumeJobsList = @()
        if ($Volumes.BackupPolicyIds -ne $null)
        {
            foreach ($BackupPolicyId in $Volume.BackupPolicyIds) {
                $BackupPolicyName = $BackupPolicyId -replace $BackupPolicyPath, ''
                $VolumeJobsList += $Jobs | Where EntityLabel -eq $BackupPolicyName
            }
        }
        

        # Add volume details
        $object = New-Object System.Object
        $object | Add-Member -Type NoteProperty -Name DeviceName -Value $DeviceName
        $object | Add-Member -Type NoteProperty -Name VolumeContainerName -Value ($Volume.VolumeContainerId -replace $VolumeContainerPath, '')
        $object | Add-Member -Type NoteProperty -Name VolumeName -Value $Volume.Name
        $object | Add-Member -Type NoteProperty -Name BackupStatus -Value $Volume.BackupStatus
        $object | Add-Member -Type NoteProperty -Name NumberOfBackupsAvailable -Value (($Backups | measure).Count)
        $object | Add-Member -Type NoteProperty -Name RunningJobs -Value (($VolumeJobsList | where Status -eq 'Running' | measure).Count)
        $object | Add-Member -Type NoteProperty -Name SucceededJobs -Value (($VolumeJobsList | where Status -eq 'Succeeded' | measure).Count)
        $object | Add-Member -Type NoteProperty -Name FailedJobs -Value (($VolumeJobsList | where Status -eq 'Failed' | measure).Count)
        $object | Add-Member -Type NoteProperty -Name CanceledJobs -Value (($VolumeJobsList | where Status -eq 'Canceled' | measure).Count)

        # Add volume object
        $VolumeStats += $object
    }

    # Print Volume stats
    if ($VolumeStats -ne $null) {
       $VolumeStats | Sort-Object {$_.VolumeContainerName, $_.VolumeName} | Format-Table -Auto
    }
    else {
        PrettyWriter "No volumes available in $DeviceName Device"
    }
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
}