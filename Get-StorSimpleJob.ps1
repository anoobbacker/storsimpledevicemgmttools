﻿<#
.DESCRIPTION
    This scipt reads lists of StorSimple Job(s).

    Steps to execute the script: 
    ----------------------------
    1.  Open powershell, create a new folder & change directory to the folder.
            > mkdir C:\scripts\StorSimpleSDKTools
            > cd C:\scripts\StorSimpleSDKTools
    
    2.  Download nuget CLI under the same folder in Step1.
        Various versions of nuget.exe are available on nuget.org/downloads. Each download link points directly to an .exe file, so be sure to right-click and save the file to your computer rather than running it from the browser. 
            > wget https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -Out :\scripts\StorSimpleSDKTools\nuget.exe
    
    3.  Download the dependent SDK
            > C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Azure.Management.Storsimple8000series
            > C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.IdentityModel.Clients.ActiveDirectory -Version 2.28.3
            > C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Rest.ClientRuntime.Azure.Authentication -Version 2.2.9-preview
    
    4.  Download the script from script center. 
            > wget https://github.com/anoobbacker/storsimpledevicemgmttools/raw/master/Get-StorSimpleJob.ps1 -Out Get-StorSimpleJob.ps1
            > .\Get-StorSimpleJob.ps1 -SubscriptionId <subid> -TenantId <tenantid> -ResourceGroupName <resource group> -ManagerName <device manager>
     
     ----------------------------
.PARAMS 

    SubscriptionId: Input the Subscription ID where the StorSimple 8000 series device manager is deployed.
    TenantId: Input the ID of the tenant of the subscription. Get using Get-AzureRmSubscription cmdlet.
    DeviceName: Input the name of the StorSimple device on which to retrieve the StorSimple job(s).
    ResourceGroupName: Input the name of the resource group on which to retrieve the StorSimple job(s).
    ManagerName: Input the name of the resource (StorSimple device manager) on which to retrieve the StorSimple job(s).
    status: Input the status of the jobs to be filtered. Valid values are: "Running", "Succeeded", "Failed" or "Canceled".
    JobType: Input type of the job to be filtered. Valid values are: "ScheduledBackup", "ManualBackup", "RestoreBackup", 
             "CloneVolume", "FailoverVolumeContainers", "CreateLocallyPinnedVolume", "ModifyVolume", "InstallUpdates",
             "SupportPackageLogs", or "CreateCloudAppliance"
    StartTime: Input the start time of the jobs to be filtered.
    EndTime: Input the end time of the jobs to be filtered.
#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Input the Subscription ID where the StorSimple 8000 series device manager is deployed.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Input the ID of the tenant of the subscription. Get using Get-AzureRmSubscription cmdlet.")]
    [String]
    $TenantId,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource group on which to retrieve the StorSimple job(s).")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource (StorSimple device manager) on which to retrieve the StorSimple job(s).")]
    [String]
    $ManagerName,

    [parameter(Mandatory = $false, HelpMessage = "Input the name of the StorSimple device on which to retrieve the StorSimple job(s).")]
    [String]
    $DeviceName,

    [parameter(Mandatory = $false, HelpMessage = "Input the status of the jobs to be filtered. Valid values are: Running, Succeeded, Failed or Canceled.")]
    [ValidateSet('Running', 'Succeeded', 'Failed', 'Canceled')]
    [String]
    $Status,

    [parameter(Mandatory = $false, HelpMessage = "Input type of the job to be filtered. Valid values are: ScheduledBackup, ManualBackup, RestoreBackup, 
               CloneVolume, FailoverVolumeContainers, CreateLocallyPinnedVolume, ModifyVolume, InstallUpdates, SupportPackageLogs, or CreateCloudAppliance")]
    [ValidateSet('ScheduledBackup', 'ManualBackup', 'RestoreBackup', 'CloneVolume', 'FailoverVolumeContainers', 'CreateLocallyPinnedVolume', 'ModifyVolume', 
                 'InstallUpdates','SupportPackageLogs','CreateCloudAppliance')]
    [String]
    $JobType,

    [parameter(Mandatory = $false, HelpMessage = "Input the start time of the jobs to be filtered.")]
    [DateTime]
    $StartTime,

    [parameter(Mandatory = $false, HelpMessage = "Input the end time of the jobs to be filtered.")]
    [DateTime]
    $EndTime
)

# Set Current directory path
$ScriptDirectory = (Get-Location).Path

#Set dll path
$ActiveDirectoryPath = Join-Path $ScriptDirectory "Microsoft.IdentityModel.Clients.ActiveDirectory.2.28.3\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
$ClientRuntimeAzurePath = Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.3.3.7\lib\net452\Microsoft.Rest.ClientRuntime.Azure.dll"
$ClientRuntimePath = Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.2.3.8\lib\net452\Microsoft.Rest.ClientRuntime.dll"
$NewtonsoftJsonPath = Join-Path $ScriptDirectory "Newtonsoft.Json.6.0.8\lib\net45\Newtonsoft.Json.dll"
$AzureAuthenticationPath = Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.Authentication.2.2.9-preview\lib\net45\Microsoft.Rest.ClientRuntime.Azure.Authentication.dll"
$StorSimple8000SeresePath = Join-Path $ScriptDirectory "Microsoft.Azure.Management.Storsimple8000series.1.0.0\lib\net452\Microsoft.Azure.Management.Storsimple8000series.dll"

#Load all required assemblies
[System.Reflection.Assembly]::LoadFrom($ActiveDirectoryPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($ClientRuntimeAzurePath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($ClientRuntimePath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($NewtonsoftJsonPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($AzureAuthenticationPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($StorSimple8000SeresePath) | Out-Null

# Print methods
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

# Define constant variables (DO NOT CHANGE BELOW VALUES)
$FrontdoorUrl = "urn:ietf:wg:oauth:2.0:oob"
$TokenUrl = "https://management.azure.com"
$DomainId = "1950a258-227b-4e31-a9cf-717495945fc2"

$FrontdoorUri = New-Object System.Uri -ArgumentList $FrontdoorUrl
$TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

$AADClient = [Microsoft.Rest.Azure.Authentication.ActiveDirectoryClientSettings]::UsePromptOnly($DomainId, $FrontdoorUri)

# Set Synchronization context
$SyncContext = New-Object System.Threading.SynchronizationContext
[System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

# Verify User Credentials
$Credentials = [Microsoft.Rest.Azure.Authentication.UserTokenProvider]::LoginWithPromptAsync($TenantId, $AADClient).GetAwaiter().GetResult()
$StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $TokenUri, $Credentials

# Set SubscriptionId
$StorSimpleClient.SubscriptionId = $SubscriptionId

$filter = ''
if ($StartTime -ne $null) {
    $filter = "starttime ge '$($StartTime.ToString('r'))'"
    if($EndTime -ne $null) {
        $filter += " and starttime le '$($EndTime.ToString('r'))'"
    }
}

if (!([string]::IsNullOrEmpty($Status)) -and $filter.Length -eq 0) {
    $filter = "status eq '$($Status)'"
} elseif (!([string]::IsNullOrEmpty($Status)) -and $filter.Length -gt 0) {
    $filter += " and status eq '$($Status)'"
}

if (!([string]::IsNullOrEmpty($JobType)) -and $filter.Length -eq 0) {
    $filter = "jobtype eq '$($JobType)'"
} elseif (!([string]::IsNullOrEmpty($JobType)) -and $filter.Length -gt 0) {
    $filter += " and jobtype eq '$($JobType)'"
}

# Get backups by Device
try {
    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.JobFilter] -ArgumentList $filter

    if ([string]::IsNullOrEmpty($DeviceName) -and $filter.Length -eq 0) {
        [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByManager($StorSimpleClient.Jobs, $ResourceGroupName, $ManagerName)
    } elseif ([string]::IsNullOrEmpty($DeviceName) -and $filter.Length -gt 0) {
        [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByManager($StorSimpleClient.Jobs, $ResourceGroupName, $ManagerName, $oDataQuery)
    } elseif ($filter.Length -gt 0) {
        [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
    } else {
        [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName)
    }
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}
