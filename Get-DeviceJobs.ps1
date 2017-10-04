<#
.DESCRIPTION
    This scipt reads lists of StorSimple Job(s).

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
            wget https://raw.githubusercontent.com/anoobbacker/storsimpledevicemgmttools/master/Get-DeviceJobs.ps1 -Out Get-DeviceJobs.ps1
            .\Get-DeviceJobs.ps1 -SubscriptionId [subid] -TenantId [tenant id] -DeviceName [name of device] -ResourceGroupName [name of resource group] -ManagerName [name of device manager] -FilterByStatus [Filter for job status] -FilterByJobType [Filter for job type] -FilterByStartTime [Filter for start date time] -FilterByEndTime [Filter for end date time] -AuthNType [Type of auth] -AADAppId [AAD app Id] -AADAppAuthNKey [AAD App Auth Key]
     
     ----------------------------
.PARAMS 

    SubscriptionId: Input the Subscription ID where the StorSimple 8000 series device manager is deployed.
    TenantId: Input the Tenant ID of the subscription. Get Tenant ID using Get-AzureRmSubscription cmdlet or go to the documentation https://aka.ms/ss8000-script-tenantid.
    
    ResourceGroupName: Input the name of the resource group on which to retrieve the StorSimple job(s).
    ManagerName: Input the name of the resource (StorSimple device manager) on which to retrieve the StorSimple job(s).
    DeviceName: Input the name of the StorSimple device on which to retrieve the StorSimple job(s).
    
    FilterByStatus: Input the status of the jobs to be filtered. Valid values are: "Running", "Succeeded", "Failed" or "Canceled".
    FilterByJobType: Input type of the job to be filtered. Valid values are: "ScheduledBackup", "ManualBackup", "RestoreBackup", 
             "CloneVolume", "FailoverVolumeContainers", "CreateLocallyPinnedVolume", "ModifyVolume", "InstallUpdates",
             "SupportPackageLogs", or "CreateCloudAppliance"
    FilterByStartTime: Input the start time of the jobs to be filtered.
    FilterByEndTime: Input the end time of the jobs to be filtered.

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
    $FilterByStatus,

    [parameter(Mandatory = $false, HelpMessage = "Input type of the job to be filtered. Valid values are: ScheduledBackup, ManualBackup, RestoreBackup, 
               CloneVolume, FailoverVolumeContainers, CreateLocallyPinnedVolume, ModifyVolume, InstallUpdates, SupportPackageLogs, or CreateCloudAppliance")]
    [ValidateSet('ScheduledBackup', 'ManualBackup', 'RestoreBackup', 'CloneVolume', 'FailoverVolumeContainers', 'CreateLocallyPinnedVolume', 'ModifyVolume', 
                 'InstallUpdates','SupportPackageLogs','CreateCloudAppliance')]
    [String]
    $FilterByJobType,

    [parameter(Mandatory = $false, HelpMessage = "Input the start time of the jobs to be filtered.")]
    [DateTime]
    $FilterByStartTime = (get-date).AddDays(-7),

    [parameter(Mandatory = $false, HelpMessage = "Input the end time of the jobs to be filtered.")]
    [DateTime]
    $FilterByEndTime = (get-date),

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

Function GenerateQueryFilter() {
    param([String] $FilterByStatus, [String] $FilterByJobType, [DateTime] $FilterByStartTime, [DateTime] $FilterByEndTime)
    $queryFilter = ''
    if ($FilterByStartTime -ne $null) {
        $queryFilter = "starttime ge '$($FilterByStartTime.ToString('r'))'"
        if($FilterByEndTime -ne $null) {
            $queryFilter += " and starttime le '$($FilterByEndTime.ToString('r'))'"
        }
    }

    if (!([string]::IsNullOrEmpty($FilterByStatus)) -and $queryFilter.Length -eq 0) {
        $queryFilter = "status eq '$($FilterByStatus)'"
    } elseif (!([string]::IsNullOrEmpty($FilterByStatus)) -and $queryFilter.Length -gt 0) {
        $queryFilter += " and status eq '$($FilterByStatus)'"
    }

    if (!([string]::IsNullOrEmpty($FilterByJobType)) -and $queryFilter.Length -eq 0) {
        $queryFilter = "jobtype eq '$($FilterByJobType)'"
    } elseif (!([string]::IsNullOrEmpty($FilterByJobType)) -and $queryFilter.Length -gt 0) {
        $queryFilter += " and jobtype eq '$($FilterByJobType)'"
    }

    return $queryFilter
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

# Generate the query filter
$filter = GenerateQueryFilter $FilterByStatus $FilterByJobType $FilterByStartTime $FilterByEndTime

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