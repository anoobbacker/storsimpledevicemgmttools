<#
.DESCRIPTION
    This scipt deletes the backup object[s].

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
            > wget https://github.com/anoobbacker/storsimpledevicemgmttools/raw/master/Remove-ExpiredDeviceBackups.ps1 -Out Remove-ExpiredDeviceBackups.ps1
            > .\Remove-ExpiredDeviceBackups.ps1 -SubscriptionId <subid> -TenantId <tenantid> -ResourceGroupName <resource group> -ManagerName <device manager> -DeviceName <device name> -BackupPolicyName <backup policy name> -RetentionInDays <retention days>
     
     ----------------------------
.PARAMS 
    SubscriptionId: Input the Subscription ID where the StorSimple 8000 series device manager is deployed.
    TenantId: Input the ID of the tenant of the subscription. Get using Get-AzureRmSubscription cmdlet or go to the documentation https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal#get-tenant-id.
    DeviceName: Input the name of the StorSimple device on which to create/update the volume.
    ResourceGroupName: Input the name of the resource group on which to create/update the volume.
    ManagerName: Input the name of the resource (StorSimple device manager) on which to create/update the volume.
    BackupPolicyName: Input the name of the Backup policy to use to create the cloud snapshot.
    RetentionInDays: Input the days of the retention to use to delete the older backups. Default value 20 days.
    WhatIf: Input the WhatIf arg as $true if you want to see what changes the script will make. Possible values [$false, $true]
#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Input the Subscription ID where the StorSimple 8000 series device manager is deployed.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Input the ID of the tenant of the subscription. Get using Get-AzureRmSubscription cmdlet.")]
    [String]
    $TenantId,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource group on which to read backup schedules and backup catalogs.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource (StorSimple device manager) on which to read backup schedules and backup catalogs.")]
    [String]
    $ManagerName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the StorSimple device on which to read backup schedules and backup catalogs.")]
    [String]
    $DeviceName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the Backup policy to use to create the cloud snapshot.")]
    [String]
    $BackupPolicyName,

    [parameter(Mandatory = $false, HelpMessage = "Input the days of the retention to use to delete the older backups. Default value 20 days.")]
    [string]
    $RetentionInDays = 20,

    [parameter(Mandatory = $false, HelpMessage = "Input the WhatIf arg if you want to see what changes the script will make.")]
    [ValidateSet($true, $false)]
    [bool]
    $WhatIf = $true
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

# Set backup expiration date
$Today = Get-Date
$ExpirationDate = $Today.AddDays(-$RetentionInDays)

# Set backup type (CloudSnapshot)
$BackupType = 'CloudSnapshot'

try {
    Write-Output "Starting start a manual backup."

    if ( $WhatIf ) 
    {
        PrettyWriter "WhatIf: Perform manual backup." "Red"
    }
    else 
    {
        $Result = [Microsoft.Azure.Management.StorSimple8000Series.BackupPoliciesOperationsExtensions]::BackupNowAsync($StorSimpleClient.BackupPolicies, $DeviceName, $BackupPolicyName, $BackupType, $ResourceGroupName, $ManagerName)
        if ($Result -ne $null -and $Result.IsFaulted) {
            Write-Output $Result.Exception
            break
        }
    }

    PrettyWriter "Successfully started the manual backup job."
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

$CompletedSnapshots =@()

# Get all backups by Device
try {
    $CompletedSnapshots = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::ListByDevice($StorSimpleClient.Backups, $DeviceName, $ResourceGroupName, $ManagerName)
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

Write-Output "Find the backup snapshots prior to $ExpirationDate ($RetentionInDays days) and delete them."
foreach ($Snapshot in $CompletedSnapshots) 
{
    $SnapShotName = $SnapShot.Name
    $SnapshotStartTimeStamp = $Snapshot.CreatedOn
    if ($SnapshotStartTimeStamp -lt $ExpirationDate)
    {
        try {
            if ( $WhatIf ) 
            {
                PrettyWriter "WhatIf: Trigger delete of snapshot $($SnapShotName) which was created on $($SnapshotStartTimeStamp)" "Red"
            }
            else 
            {
                PrettyWriter "Deleting $($SnapShotName) which was created on $($SnapshotStartTimeStamp)."
                $Result = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::DeleteAsync($StorSimpleClient.Backups, $DeviceName, $SnapShotName, $ResourceGroupName, $ManagerName)
                if ($Result -ne $null -and $Result.IsFaulted) {
                    Write-Error $Result.Exception
                }
            }
        }
        catch {
            # Print error details
            Write-Error $_.Exception.Message
            break
        } 
    }
    else
    {
        #Write-Output "Skipping $SnapShotName at $SnapshotStartTimeStamp"
    }
}
