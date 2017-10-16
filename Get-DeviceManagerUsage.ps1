<#
.DESCRIPTION
    This scipt lists StorSimple device manager and usages of the devices under the manager.

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
            wget https://raw.githubusercontent.com/anoobbacker/storsimpledevicemgmttools/master/Get-DeviceManagerUsage.ps1 -Out Get-DeviceManagerUsage.ps1
            .\Get-DeviceManagerUsage.ps1 -SubscriptionId [subid] -TenantId [tenantid] -ResourceGroupName [resource group] -ManagerName [device manager] -AuthNType [Type of auth] -AADAppId [AAD app Id] -AADAppAuthNKey [AAD App Auth Key]
     
     ----------------------------
.PARAMS 

    SubscriptionId: Input the Subscription ID where the StorSimple 8000 series device manager is deployed.
    TenantId: Input the Tenant ID of the subscription. Get Tenant ID using Get-AzureRmSubscription cmdlet or go to the documentation https://aka.ms/ss8000-script-tenantid.
    
    ResourceGroupName: Input the name of the resource group on which to create/update the volume.
    ManagerName: Input the name of the resource (StorSimple device manager) on which to create/update the volume.

    FilterByStartTime: Input the start time of the capacity utilization. Eg: (Get-Date -Date "2017-01-01 10:30")
    FilterByEndTime: Input the end time of the capacity utilization. Eg: (Get-Date -Date "2017-01-01 10:30")

    AuthNType: Input if you want to go with username, AAD authentication key or certificate. Possible values: [UserNamePassword, AuthenticationKey, Certificate]. Refer https://aka.ms/ss8000-script-sp. 
    
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

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource group on which to read backup schedules and backup catalogs.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Input the name of the resource (StorSimple device manager) on which to read backup schedules and backup catalogs.")]
    [String]
    $ManagerName,

    [parameter(Mandatory = $false, HelpMessage = "Input the start time of the capacity utilization.")]
    [DateTime]
    $FilterByStartTime = (get-date).AddDays(-1),

    [parameter(Mandatory = $false, HelpMessage = "Input the end time of the capacity utilization.")]
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

# Print method
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

Function GenerateCapacityFilter() {
    param([DateTime] $FilterByStartTime, [DateTime] $FilterByEndTime)
    $queryFilter = $null
    if ($FilterByStartTime -ne $null) {
        $queryFilter = "startTime ge '$($FilterByStartTime.ToString('r'))'"
    }

    if($FilterByEndTime -ne $null) {
        if(![string]::IsNullOrEmpty($queryFilter)) {
            $queryFilter += " and "
        }
        $queryFilter += "endTime  le '$($FilterByEndTime.ToString('r'))'"
    }

    if(![string]::IsNullOrEmpty($queryFilter)) {
        $queryFilter += " and timeGrain eq 'PT1H' and category eq 'CapacityUtilization'"
    } else {
        $queryFilter += "timeGrain eq 'PT1H' and category eq 'CapacityUtilization'"
    }

    return $queryFilter
}

Function Convert-Value {
    param(      
        [validateset("Bytes","KB","MB","GB","TB")]            
        [String]$To,            
        [Parameter(Mandatory=$true)]            
        [double]$Value,            
        [int]$Precision = 1
    )

    switch ($To) {            
        "Bytes" {return $Value}            
        "KB" {$Value = $Value/1KB}
        "MB" {$Value = $Value/1MB}            
        "GB" {$Value = $Value/1GB}            
        "TB" {$Value = $Value/1TB}                
    }

    return [Math]::Round($Value,$Precision,[MidPointRounding]::AwayFromZero)
}

Function Convert-Size {
    param(
        [validateset("Bytes","KB","MB","GB","TB")]          
        [String]$From,           
        [Parameter(Mandatory=$true)]            
        [double]$Value,            
        [int]$Precision = 1            
    )            
    switch($From) {            
        "Bytes" {$value = $Value }            
        "KB" {$value = $Value * 1024 }            
        "MB" {$value = $Value * 1024 * 1024}            
        "GB" {$value = $Value * 1024 * 1024 * 1024}            
        "TB" {$value = $Value * 1024 * 1024 * 1024 * 1024}            
    }            
    
    $tUnit = "TB"
    $tValue = Convert-Value $tUnit $value
    if ( $tValue -eq 0 ) {
        $tUnit = "GB"
        $tValue = Convert-Value $tUnit $value $Precision
    }
    if ( $tValue -eq 0 ) {
        $tUnit = "MB"
        $tValue = Convert-Value $tUnit $value $Precision
    }
    if ( $tValue -eq 0 ) {
        $tUnit = "KB"
        $tValue = Convert-Value $tUnit $value $Precision
    }
    if ( $tValue -eq 0 ) {
        $tUnit = "Bytes"
        $tValue = Convert-Value $tUnit $value $Precision
    }        

    return "$tValue $tUnit"
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

# Get backups by Device
try {
    #Generate query filter for the metrics.
    $BackupQuery = GenerateCapacityFilter $FilterByStartTime $FilterByEndTime    
    $oDataQuery = New-Object Microsoft.Rest.Azure.OData.ODataQuery[Microsoft.Azure.Management.StorSimple8000Series.Models.MetricFilter] -ArgumentList $BackupQuery

    #Get the metrics values
    $Metrics = [Microsoft.Azure.Management.StorSimple8000Series.ManagersOperationsExtensions]::ListMetrics($StorSimpleClient.Managers, $oDataQuery, $ResourceGroupName, $ManagerName)

    # Print usage
    if ($Metrics -ne $null -and $Metrics.Length -gt 0) {
        #Metrics: PrimaryStorageTieredUsed, PrimaryStorageLocallyPinnedUsed, CloudStorageUsed
        foreach ($Metric in $Metrics) 
        {
            $MetricsName =$Metric.Name.Value
            $MetricsDisplayName = $Metric.Name.LocalizedValue
            $MetricsCount = $Metric.Values.Count
            $LatestMetricsValue = $Metric.Values[$MetricsCount-1].Maximum
            $DisplayUsageValue = Convert-Size "Bytes" $LatestMetricsValue
            PrettyWriter "Latest $MetricsDisplayName - $DisplayUsageValue"
        }
    } else {
        Write-Error "No metric(s) available."
    }

    $Devices = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::ListByManager($StorSimpleClient.Devices, $ResourceGroupName, $ManagerName)
    # Print device usage
    
    $DeviceUsageStats = @()
    if ($Devices -ne $null -and $Devices.Length -gt 0) {
        #Usage fields: AvailableLocalStorageInBytes, AvailableTieredStorageInBytes, ProvisionedTieredStorageInBytes, ProvisionedLocalStorageInBytes, ProvisionedVolumeSizeInBytes, UsingStorageInBytes, TotalTieredStorageInBytes
        foreach ($Device in $Devices) 
        {
            $AvailableLocalStorage = Convert-Size "Bytes"  $Device.AvailableLocalStorageInBytes
            $AvailableTieredStorage = Convert-Size "Bytes" $Device.AvailableTieredStorageInBytes
            $RemainingLocalStorageBytes = ($Device.AvailableLocalStorageInBytes - $Device.UsingStorageInBytes)
            $RemainingLocalStorage = Convert-Size "Bytes" $RemainingLocalStorageBytes
            $ProvisionedTieredStorage = Convert-Size "Bytes" $Device.ProvisionedTieredStorageInBytes
            $ProvisionedLocalStorage = Convert-Size "Bytes" $Device.ProvisionedLocalStorageInBytes
            $ProvisionedVolumeSize = Convert-Size "Bytes" $Device.ProvisionedVolumeSizeInBytes
            $UsingStorage = Convert-Size "Bytes" $Device.UsingStorageInBytes            
            $object = New-Object System.Object
            $object | Add-Member –Type NoteProperty –Name "Device Name" -Value $Device.Name            
            #StorSimple cloud appliances (8010/8020) doesn't support locally-pinned volumes.
            if ( $Device.ModelDescription -ne "8010" -and $Device.ModelDescription -ne "8020" ) {
                $object | Add-Member –Type NoteProperty –Name "Available" -Value "Local=$AvailableLocalStorage Or Tiered=$AvailableTieredStorage"  
            } else {
                $object | Add-Member –Type NoteProperty –Name "Available" -Value "Tiered=$AvailableTieredStorage"     
            }


            #Provisioned Tiered Storage
            $object | Add-Member –Type NoteProperty –Name "Prov. Tiered" -Value "$ProvisionedTieredStorage"
            
            #StorSimple cloud appliances (8010/8020) doesn't support locally-pinned volumes.
            #Provisioned Local Storage
            if ( $Device.ModelDescription -ne "8010" -and $Device.ModelDescription -ne "8020" ) {
                $object | Add-Member –Type NoteProperty –Name "Prov. Local" -Value "$ProvisionedLocalStorage"
            } else {
                $object | Add-Member –Type NoteProperty –Name "Prov. Local" -Value "-"
            }
            
            $object | Add-Member –Type NoteProperty –Name "Prov. Volume" -Value "$ProvisionedVolumeSize"
            $object | Add-Member –Type NoteProperty –Name "Usage" -Value "$UsingStorage"
            
            if ( $Device.ModelDescription -eq "8100" ) {
                #$MaximumCapacityBytes = 200 * 1024 * 1024 * 1024 * 1024
                $object | Add-Member –Type NoteProperty –Name "Max" -Value "200TB"                
            } elseif ( $Device.ModelDescription -eq "8600" ) {
                #$MaximumCapacityBytes = 500 * 1024 * 1024 * 1024 * 1024
                $object | Add-Member –Type NoteProperty –Name "Max" -Value "500TB"
            } else {                
                #$MaximumCapacityBytes = 30 * 1024 * 1024 * 1024 * 1024
                $object | Add-Member –Type NoteProperty –Name "Max" -Value "30TB"
            }
            $DeviceUsageStats += $object  
        }
    } else {
        Write-Error "No device(s) available."
    }    
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

# Print result
$DeviceUsageStats | Format-Table -Auto
