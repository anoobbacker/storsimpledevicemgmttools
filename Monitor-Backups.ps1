<#
.DESCRIPTION
    This Azure Automation Runbook powershell scipt reports the status of all backup jobs.

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
    
    4.  Download the script from github. 
            > wget https://github.com/anoobbacker/storsimpledevicemgmttools/raw/master/Monitor-Backup.ps1 -Out Monitor-Backup.ps1
     
    5. Create an Azure automation account with Azure RunAs Account. Refer https://docs.microsoft.com/azure/automation/automation-create-standalone-account. 
    
        If you've an existing Azure automation account configure the Azure RunAs Account, refer https://docs.microsoft.com/azure/automation/automation-create-runas-account.

    6. Create an Azure Automation Runbook Module for StorSimple 8000 Series device management. Use the below commands to create a Automation module zip file.

            # set 
            $downloadDir = "C:\scripts\StorSimpleSDKTools"

            #don't change the folder name "Microsoft.Azure.Management.StorSimple8000Series"
            mkdir "$downloadDir\AutomationModule\Microsoft.Azure.Management.StorSimple8000Series"
            copy "$downloadDir\Microsoft.IdentityModel.Clients.ActiveDirectory.2.28.3\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Rest.ClientRuntime.Azure.3.3.7\lib\net452\Microsoft.Rest.ClientRuntime.Azure*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Rest.ClientRuntime.2.3.8\lib\net452\Microsoft.Rest.ClientRuntime*.dll" $moduleDir
            copy "$downloadDir\Newtonsoft.Json.6.0.8\lib\net45\Newtonsoft.Json*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Rest.ClientRuntime.Azure.Authentication.2.2.9-preview\lib\net45\Microsoft.Rest.ClientRuntime.Azure.Authentication*.dll" $moduleDir
            copy "$downloadDir\Microsoft.Azure.Management.Storsimple8000series.1.0.0\lib\net452\Microsoft.Azure.Management.Storsimple8000series*.dll" $moduleDir

            #Don't change the name of the Archive
            compress-Archive -Path "$downloadDir\AutomationModule\Microsoft.Azure.Management.StorSimple8000Series" -DestinationPath Microsoft.Azure.Management.StorSimple8000Series.zip

    7. Import the Azure Automation module zip file (Microsoft.Azure.Management.StorSimple8000Series.zip) created in above step. This can be done by selecting the Automation Account, click "Modules" under SHARED RESOURCES and then click "Add a module". 

    8. Import the runbook script (Monitor-Backup.ps1) as a Azure Automation Powershell runbook script, publish & execute it.

     ----------------------------
.PARAMS
    ResourceGroupName: Input the name of the resource group on which to retrieve the StorSimple job(s).
    ManagerName: Input the name of the resource (StorSimple device manager) on which to retrieve the StorSimple job(s).
    DeviceName: Input the name of the StorSimple device on which to retrieve the StorSimple job(s).
    NumberOfDaysForReport: Input the number of days for which to get Backup status report.
#>

param
(
    [Parameter(Mandatory = $true, HelpMessage = "Input the name of the resource group on which to retrieve the StorSimple job(s).")]
    [String]
    $ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "Input the name of the resource (StorSimple device manager) on which to retrieve the StorSimple job(s).")]
    [String]
    $ManagerName,

    [Parameter(Mandatory = $true, HelpMessage = "Input the name of the StorSimple device on which to retrieve the StorSimple job(s).")]
    [String]
    $DeviceName,

	[Parameter(Mandatory=$false, HelpMessage = "Input the number of days to get Backups status report.")]
	[int]
    $NumberOfDaysForReport
)

function GenerateFilterODataQuery()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$filterByStatus,

        [Parameter(Mandatory = $true)]
        [int]$filterByDuration
    )

    $filter = "jobtype eq 'ScheduledBackup'"
    $filterByStartTime = (Get-Date).AddDays(-($filterByDuration))
    $filterByEndTime = (Get-Date)

    if (!([string]::IsNullOrEmpty($filterByStatus))) {
        $filter += " and status eq '$($filterByStatus)'"
    }

    if (!([string]::IsNullOrEmpty($filterByDuration))) {
        $filter += " and starttime ge '$($filterByStartTime.ToString('r'))' and starttime le '$($filterByEndTime.ToString('r'))'"
    }

    return $filter
}

function GetDurationTime()
{
    param
    (
        [Parameter(Mandatory = $true)]
        [datetime]$JobStartTime,
        [Parameter(Mandatory = $true)]
        [datetime]$JobEndTime
    )
    
    $durationInString = ""
    $Duration = ([datetime]$JobEndTime) - ([datetime]$JobStartTime)

    if ($Duration.Days -eq 1) { $durationInString += "$($Duration.Days) day"}
    elseif ($Duration.Days -gt 1) { $durationInString += "$($Duration.Days) days"}
    
    if ($durationInString.Length -eq 0) {
        if ($Duration.Hours -eq 1) { $durationInString += "$($Duration.Hours) hour"}
        elseif ($Duration.Hours -gt 1) { $durationInString += "$($Duration.Hours) hours"}
    }else {
        if ($Duration.Hours -eq 1) { $durationInString += " and $($Duration.Hours) hour"}
        elseif ($Duration.Hours -gt 1) { $durationInString += " and $($Duration.Hours) hours"}
    }

    if ($durationInString.Length -eq 0) {
        if ($Duration.Minutes -eq 1) { $durationInString += "$($Duration.Minutes) minute"}
        elseif ($Duration.Minutes -gt 1) { $durationInString += "$($Duration.Minutes) minutes"}
    }else {
        if ($Duration.Minutes -eq 1) { $durationInString += " and $($Duration.Minutes) minute"}
        elseif ($Duration.Minutes -gt 1) { $durationInString += " and $($Duration.Minutes) minutes"}
    }

    if ($durationInString.Length -eq 0) {
        if ($Duration.Seconds -eq 1) { $durationInString += "$($Duration.Seconds) second"}
        elseif ($Duration.Seconds -gt 1) { $durationInString += "$($Duration.Seconds) seconds"}
    }else {
        if ($Duration.Seconds -eq 1) { $durationInString += " and $($Duration.Seconds) second"}
        elseif ($Duration.Seconds -gt 1) { $durationInString += " and $($Duration.Seconds) seconds"}
    }

    return $durationInString
}

function EnumerateJobs()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [Object]$PolictyToVolumeList,

        [Parameter(Mandatory = $true)]
        [Object]$Jobs
    )

    $JobsHistory = @()
    foreach ($job in $Jobs)
    {
        $VolumeNames = ($PolictyToVolumeList | where BackupPolicyName -eq $job.EntityLabel).Volumes
        $durationInString = GetDurationTime $job.StartTime $job.EndTime
        $ErrorDetails = ($job.Error | select Message).Message -Join ', '

        $object = New-Object System.Object
        $object | Add-Member –Type NoteProperty –Name BackupPolicyName -Value $job.EntityLabel
        $object | Add-Member –Type NoteProperty –Name Volumes -Value $VolumeNames
        $object | Add-Member –Type NoteProperty –Name JobType -Value $job.JobType
        $object | Add-Member –Type NoteProperty –Name BackupType -Value $job.BackupType
        $object | Add-Member –Type NoteProperty –Name Status -Value $job.Status
        $object | Add-Member –Type NoteProperty –Name StartTime -Value $job.StartTime
        $object | Add-Member –Type NoteProperty –Name EndTime -Value $job.EndTime
        $object | Add-Member –Type NoteProperty –Name Duration -Value $durationInString
        $object | Add-Member –Type NoteProperty –Name 'Error Message' $ErrorDetails

        $JobsHistory += $object
    }

    return $JobsHistory
}

$SLEEPTIMEOUT = 10    # Value in seconds
$BaseUrl = "https://management.azure.com"

$ServicePrincipalConnection = Get-AutomationConnection -Name AzureRunAsConnection
if ($ServicePrincipalConnection -eq $null)  { 
    throw "Either AzureRunAsConnection asset has not been created in the Automation service or you're not running the script in an Azure automation account."  
}

# Get service principal details
$SubscriptionId = $ServicePrincipalConnection.SubscriptionId
if ($SubscriptionId -eq $null) {
   throw "Could not retrieve subscription."
}

$TenantId = $ServicePrincipalConnection.TenantId
if ($TenantId -eq $null) {
   throw "Could not retrieve TenantId."
}

$ClientId = $ServicePrincipalConnection.ApplicationId
if ($TenantId -eq $null) {
   throw "Could not retrieve ApplicationId."
}

$ClientCertificate = Get-AutomationCertificate -Name AzureRunAsCertificate
if ($ClientCertificate -eq $null) {
   throw "Could not retrieve certificate."
}

# Set Current directory path
$ScriptDirectory = "C:\Modules\User\Microsoft.Azure.Management.StorSimple8000Series"

# Load all dependent dlls
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.IdentityModel.Clients.ActiveDirectory.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Newtonsoft.Json.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.Authentication.dll")) | Out-Null
[Reflection.Assembly]::LoadFile((Join-Path $ScriptDirectory "Microsoft.Azure.Management.Storsimple8000series.dll")) | Out-Null

$SyncContext = New-Object System.Threading.SynchronizationContext
[System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

$BaseUri = New-Object System.Uri -ArgumentList $BaseUrl

$ClientAssertionCertificate = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.ClientAssertionCertificate -ArgumentList $ClientId, $ClientCertificate

# Verify User Credentials
Write-Verbose "Connecting to Azure [SubscriptionId = $SubscriptionId][TenantID = $TenantId][ApplicationID = $ClientId][Certificate = $ClientCertificate.Subject]"
$Credentials = [Microsoft.Rest.Azure.Authentication.ApplicationTokenProvider]::LoginSilentWithCertificateAsync($TenantId, $ClientAssertionCertificate).GetAwaiter().GetResult()
if ($Credentials -eq $null) {
   throw "Failed to authenticate!"
}

try {
    $StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $BaseUri, $Credentials

    # Sleep before connecting to Azure (PowerShell)
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

# Get all backup policies under device
try {
    $backupPolicies = [Microsoft.Azure.Management.StorSimple8000Series.BackupPoliciesOperationsExtensions]::ListByDevice($StorSimpleClient.BackupPolicies, $DeviceName, $ResourceGroupName, $ManagerName)
} catch {
    throw $_.Exception
}

$PolictyToVolumeList = @()
foreach ($BackupPolicy in $BackupPolicies) {
    # Fetch volume name(s)
    $VolumeNames = ($BackupPolicy.VolumeIds | % {
                        if($_.Length -gt 0) {
                            $_.split(',') | % { $_.SubString($_.LastIndexOf('/') + 1) }
                        }
                    }) -Join ','

    $object = New-Object System.Object
    $object | Add-Member –Type NoteProperty –Name BackupPolicyName –Value $BackupPolicy.Name
    $object | Add-Member –Type NoteProperty –Name Volumes –Value $VolumeNames
    $PolictyToVolumeList += $object
}

# Generate oDataQuery based on JobStatus & Duration
$oDataQuery = GenerateFilterODataQuery 'Failed' $NumberOfDaysForReport

# Get all device jobs alon with query filter
try {
    $FailedJobs = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
} catch {
    throw $_.Exception
}

# Enumerate failed jobs
if ($FailedJobs -ne $null -and $FailedJobs.Length -gt 0) {
    $JobsHistory = EnumerateJobs $PolictyToVolumeList $FailedJobs
}

# Generate oDataQuery based on JobStatus & Duration
$oDataQuery = GenerateFilterODataQuery 'Running' $NumberOfDaysForReport

# Get all device jobs alon with query filter
try {
    $RunningJobs += [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
} catch {
    throw $_.Exception
}

# Enumerate failed jobs
if ($RunningJobs -ne $null -and $RunningJobs.Length -gt 0) {
    $JobsHistory += EnumerateJobs $PolictyToVolumeList $RunningJobs
}

# Generate oDataQuery based on JobStatus & Duration
$oDataQuery = GenerateFilterODataQuery 'Succeeded' $NumberOfDaysForReport

# Get all device jobs alon with query filter
try {
    $SucceededJobs = [Microsoft.Azure.Management.StorSimple8000Series.JobsOperationsExtensions]::ListByDevice($StorSimpleClient.Jobs, $DeviceName, $ResourceGroupName, $ManagerName, $oDataQuery)
} catch {
    throw $_.Exception
}

# Enumerate failed jobs
if ($SucceededJobs -ne $null -and $SucceededJobs.Length -gt 0) {
    $JobsHistory += EnumerateJobs $PolictyToVolumeList $SucceededJobs
}

# Print result
$JobsHistory | Format-Table -GroupBy Status -Auto
