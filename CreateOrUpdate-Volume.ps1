<#
.DESCRIPTION
    This script creates or updates a StorSimple 8000 series volume.

    Steps to execute the script: 
    ----------------------------
    1.  Open powershell, create a new folder & change directory to the folder.
            > mkdir C:\scripts\StorSimpleSDKTools
            > cd C:\scripts\StorSimpleSDKTools
    
    2.  Download nuget CLI under the same folder in Step1.
        Various versions of nuget.exe are available on nuget.org/downloads. Each download link points directly to an .exe file, so be sure to right-click and save the file to your computer rather than running it from the browser. 
            > wget https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -Out nuget.exe
    
    3.  Download the dependent SDK
            > C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Azure.Management.Storsimple8000series
            > C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.IdentityModel.Clients.ActiveDirectory -Version 2.28.3
            > C:\scripts\StorSimpleSDKTools\nuget.exe install Microsoft.Rest.ClientRuntime.Azure.Authentication -Version 2.2.9-preview
    
    4.  Download the script from script center. 
            > wget https://github.com/anoobbacker/storsimpledevicemgmttools/blob/master/CreateOrUpdate-Volume.ps1 -Out CreateOrUpdate-Volume.ps1
     
     ----------------------------
.PARAMS 

    SubscriptionId: Input the Subscription ID where the StorSimple 8000 series device manager is deployed.
    ResourceGroupName: Input the name of the resource group.
    ManagerName: Input the name of the StorSimple device manager.
    DeviceName: Input the name of the StorSimple device.
    VolumeContainerName: Input an existing volume container name.
    VolumeName: Input the name of the new/existing volume.
    VolumeSizeInBytes: Input the volume size in bytes. The volume size must be between 1GB to 64TB.
    VolumeType (Optional): Input the type of volume. Valid values are: Tiered or Archival or LocallyPinned. Default is Tiered.
    ConnectedHostName (Optional): Input an existing access control record. Default is no ACR.
    EnableMonitoring (Optional): Input whether to enable monitoring for the volume. Default is disabled.
#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Input the Subscription ID where the StorSimple 8000 series device manager is deployed.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource group.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the StorSimple device manager.")]
    [String]
    $ManagerName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the StorSimple device.")]
    [String]
    $DeviceName,

    [parameter(Mandatory = $true, HelpMessage = "Input an existing volume container name.")]
    [String]
    $VolumeContainerName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the new/existing volume.")]
    [String]
    $VolumeName,

    [parameter(Mandatory = $true, HelpMessage = "Input the volume size in bytes. The volume size must be between 1GB to 64TB.")]
    [Int64]
    $VolumeSizeInBytes,

    [parameter(Mandatory = $false, HelpMessage = "Input the type of volume. Valid values are: Tiered or Archival or LocallyPinned. Default is Tiered.")]
    [ValidateSet('Tiered', 'Archival', 'LocallyPinned')]
    [String]
    $VolumeType,

    [parameter(Mandatory = $false, HelpMessage = "Input an existing access control record. Default is no ACR.")]
    [String]
    $ConnectedHostName,

    [parameter(Mandatory = $false, HelpMessage = "Input whether to enable monitoring for the volume. Default is disabled.")]
    [ValidateSet("true", "false", "1", "0")]
    [string]
    $EnableMonitoring
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

#Valiate volume size
$MinimumVolumeSize = 1000000000 # 1GB
$MaximumVolumeSize = (1000000000000 * 64) # 64TB
if (!($VolumeSizeInBytes -ge $MinimumVolumeSize -and $VolumeSizeInBytes -le $MaximumVolumeSize)) {
    Write-Error "The volume size (in bytes) must be between 1GB to 64TB."
    break
}

# Define constant variables (DO NOT CHANGE BELOW VALUES)
$FrontdoorUrl = "urn:ietf:wg:oauth:2.0:oob"
$TokenUrl = "https://management.azure.com"
$TenantId = "1950a258-227b-4e31-a9cf-717495945fc2"
$DomainId = "72f988bf-86f1-41af-91ab-2d7cd011db47"

$FrontdoorUri = New-Object System.Uri -ArgumentList $FrontdoorUrl
$TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

$AADClient = [Microsoft.Rest.Azure.Authentication.ActiveDirectoryClientSettings]::UsePromptOnly($TenantId, $FrontdoorUri)

# Set Synchronization context
$SyncContext = New-Object System.Threading.SynchronizationContext
[System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

# Verify User Credentials
$Credentials = [Microsoft.Rest.Azure.Authentication.UserTokenProvider]::LoginWithPromptAsync($DomainId, $AADClient).GetAwaiter().GetResult()
$StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $TokenUri, $Credentials

# Set SubscriptionId
$StorSimpleClient.SubscriptionId = $SubscriptionId

# Get Access control record id
$AccessControlRecordIds = New-Object "System.Collections.Generic.List[String]"
if ($ConnectedHostName -ne $null -and $ConnectedHostName.Length -gt 0) {
    try {
        $acr = [Microsoft.Azure.Management.StorSimple8000Series.AccessControlRecordsOperationsExtensions]::Get($StorSimpleClient.AccessControlRecords, $ConnectedHostName, $ResourceGroupName, $ManagerName)

        if ($acr -eq $null) {
            Write-Error "Could not find an access control record with given name $($ConnectedHostName)."
            break
        }
    }
    catch {
        # Print error details
        Write-Error $_.Exception.Message
        break
    }

    $AccessControlRecordIds.Add($acr.Id)
}

# Set Monitoring status
$MonitoringStatus = [Microsoft.Azure.Management.StorSimple8000Series.Models.MonitoringStatus]::Disabled
if ([string]$EnableMonitoring -eq "true" -or $EnableMonitoring -eq 1) {
    $MonitoringStatus = [Microsoft.Azure.Management.StorSimple8000Series.Models.MonitoringStatus]::Enabled
}

# Set VolumeAppType
$VolumeAppType = $VolumeAppType = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeType]::Tiered
if ($VolumeType -eq "LocallyPinned") {
    $VolumeAppType = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeType]::LocallyPinned
} elseif ($VolumeType -eq "Archival") {
    $VolumeAppType = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeType]::Archival
}

# Set Volume properties
$VolumeProperties = New-Object Microsoft.Azure.Management.StorSimple8000Series.Models.Volume
$VolumeProperties.SizeInBytes = $VolumeSizeInBytes
$VolumeProperties.VolumeType = $VolumeAppType
$VolumeProperties.VolumeStatus = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeStatus]::Online
$VolumeProperties.MonitoringStatus = $MonitoringStatus
$VolumeProperties.AccessControlRecordIds = $AccessControlRecordIds

try {
    $Volume = [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::CreateOrUpdate($StorSimpleClient.Volumes, $DeviceName, $VolumeContainerName, $VolumeName, $VolumeProperties, $ResourceGroupName, $ManagerName)
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

# Print success message
PrettyWriter "Volume ($($VolumeName)) successfully created/updated.`n"
