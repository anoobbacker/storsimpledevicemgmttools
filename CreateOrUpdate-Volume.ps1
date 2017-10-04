<#
.DESCRIPTION
    This script creates or updates a StorSimple 8000 series volume.

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
            wget https://github.com/anoobbacker/storsimpledevicemgmttools/blob/master/CreateOrUpdate-Volume.ps1 -Out CreateOrUpdate-Volume.ps1
            .\CreateOrUpdate-Volume.ps1 -SubscriptionId [subid] -TenantId [tenantid] -ResourceGroupName [resource group] -ManagerName [device manager] -DeviceName [device name] -VolumeContainerName [volume container] -VolumeName [volume name] -VolumeSizeInBytes [volume size] -AuthNType [Type of auth] -AADAppId [AAD app Id] -AADAppAuthNKey [AAD App Auth Key]
     ----------------------------
.PARAMS 

    SubscriptionId: Input the Subscription ID where the StorSimple 8000 series device manager is deployed.
    TenantId: Input the ID of the tenant of the subscription. Get using Get-AzureRmSubscription cmdlet.
    
    ResourceGroupName: Input the name of the resource group.
    ManagerName: Input the name of the StorSimple device manager.
    DeviceName: Input the name of the StorSimple device.

    VolumeContainerName: Input an existing volume container name.
    VolumeName: Input the name of the new/existing volume.
    VolumeSizeInBytes: Input the volume size in bytes. The volume size must be between 1GB to 64TB.
    VolumeType (Optional): Input the type of volume. Valid values are: Tiered or Archival or LocallyPinned. Default is Tiered.
    ConnectedHostName (Optional): Input an existing access control record. Default is no ACR.
    EnableMonitoring (Optional): Input whether to enable monitoring for the volume. Default is disabled.
    
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
    $EnableMonitoring,

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

# Set Current directory path
$ScriptDirectory = (Get-Location).Path

# Set dll path
$ActiveDirectoryPath = Join-Path $ScriptDirectory "Microsoft.IdentityModel.Clients.ActiveDirectory.2.28.3\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
$ClientRuntimeAzurePath = Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.3.3.7\lib\net452\Microsoft.Rest.ClientRuntime.Azure.dll"
$ClientRuntimePath = Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.2.3.8\lib\net452\Microsoft.Rest.ClientRuntime.dll"
$NewtonsoftJsonPath = Join-Path $ScriptDirectory "Newtonsoft.Json.6.0.8\lib\net45\Newtonsoft.Json.dll"
$AzureAuthenticationPath = Join-Path $ScriptDirectory "Microsoft.Rest.ClientRuntime.Azure.Authentication.2.2.9-preview\lib\net45\Microsoft.Rest.ClientRuntime.Azure.Authentication.dll"
$StorSimple8000SeresePath = Join-Path $ScriptDirectory "Microsoft.Azure.Management.Storsimple8000series.1.0.0\lib\net452\Microsoft.Azure.Management.Storsimple8000series.dll"

# Load all required assemblies
[System.Reflection.Assembly]::LoadFrom($ActiveDirectoryPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($ClientRuntimeAzurePath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($ClientRuntimePath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($NewtonsoftJsonPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($AzureAuthenticationPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($StorSimple8000SeresePath) | Out-Null

# Print method
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

# Valiate volume size
$MinimumVolumeSize = 1000000000 # 1GB
$MaximumVolumeSize = (1000000000000 * 64) # 64TB
if (!($VolumeSizeInBytes -ge $MinimumVolumeSize -and $VolumeSizeInBytes -le $MaximumVolumeSize)) {
    Write-Error "The volume size (in bytes) must be between 1GB to 64TB."
    break
}

# Define constant variables (DO NOT CHANGE BELOW VALUES)
$FrontdoorUrl = "urn:ietf:wg:oauth:2.0:oob"
$TokenUrl = "https://management.azure.com"   # Run 'Get-AzureRmEnvironment | Select-Object Name, ResourceManagerUrl' cmdlet to get the Fairfax url.
$DomainId = "1950a258-227b-4e31-a9cf-717495945fc2"

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
    if ( [string]::IsNullOrEmpty($AADAppId) -or [string]::IsNullOrEmpty($AADAppAuthNKey) ) {
        throw "Invalid inputs! Ensure that you input the arguments -AADAppId and -AADAppAuthNKey."
    }

    $Credentials =[Microsoft.Rest.Azure.Authentication.ApplicationTokenProvider]::LoginSilentAsync($TenantId, $AADAppId, $AADAppAuthNKey).GetAwaiter().GetResult();
} elseif ("Certificate".Equals($AuthNType) ) {
    # AAD Service Principal Certificates
    if ( [string]::IsNullOrEmpty($AADAppId) -or [string]::IsNullOrEmpty($AADAppAuthNCertPassword) -or [string]::IsNullOrEmpty($AADAppAuthNCertPath) ) {
        throw "Invalid inputs! Ensure that you input the arguments -AADAppId, -AADAppAuthNCertPath and -AADAppAuthNCertPassword."
    }    
    if ( !(Test-Path $AADAppAuthNCertPath) ) {
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
