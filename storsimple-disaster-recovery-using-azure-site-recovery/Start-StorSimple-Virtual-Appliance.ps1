<#
.DESCRIPTION
    This runbook starts the StorSimple Virtual Appliance (SVA) in case it is in a shut down state
     
.ASSETS 
    [You can choose to encrypt these assets ]

    The following have to be added with the Recovery Plan Name as a prefix, eg - TestPlan-StorSimRegKey [where TestPlan is the name of the recovery plan]
    [All these are String variables]

    BaseUrl: The resource manager url of the Azure cloud. Get using "Get-AzureRmEnvironment | Select-Object Name, ResourceManagerUrl" cmdlet.
    'RecoveryPlanName'-ResourceGroupName: The name of the resource group on which to read storsimple virtual appliance info
    'RecoveryPlanName'-ResourceName: The name of the StorSimple resource
    'RecoveryPlanName'-TargetDeviceName: The Device on which the containers are to be failed over (the one which needs to be switched on)
    
.NOTES
    If the SVA is online, then this script will be skipped
#>
workflow Start-StorSimple-Virtual-Appliance
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

    $ClientCertificate = Get-AutomationCertificate -Name AzureRunAsCertificate
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
    $SLEEPTIMEOUT = 10 #Value in seconds
    
    InlineScript 
    {
        $BaseUrl = $Using:BaseUrl
        $SubscriptionId = $Using:SubscriptionId
        $TenantId = $Using:TenantId
        $ClientId = $Using:ClientId
        $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT
        $TargetDeviceName = $Using:TargetDeviceName
        $ResourceGroupName = $Using:ResourceGroupName
        $ManagerName = $Using:ManagerName
        $ClientCertificate = $Using:ClientCertificate       

        # Set Current directory path
        $ScriptDirectory = "C:\Modules\User\Microsoft.Azure.Management.StorSimple8000Series"
        #ls $ScriptDirectory

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
            $TargetDevice = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::Get($StorSimpleClient.Devices, $TargetDeviceName, $ResourceGroupName, $ManagerName)
        } catch {
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
        
        if ($TargetDevice -eq $null) {
            throw "Target device ($TargetDeviceName) does not exist"
        }

        # Check whether the Target Device is online or not
        if ($TargetDevice.Status -ne "Online")
        {
            Write-Output "Starting the SVA VM"
            $RetryCount = 0
            while ($RetryCount -lt 2)
            {
                $Result = Start-AzureRmVM -Name $TargetDeviceName -ResourceGroupName $ResourceGroupName
                if ($Result -ne $null -and ($Result.OperationStatus -eq "Succeeded" -or $Result.Status -eq "OK" -or $Result.StatusCode -eq "OK")) {
                    Write-Output "SVA VM succcessfully turned on"
                    break
                }
                else {
                    if ($RetryCount -eq 0) {
                        Write-Output "Retrying turn on of the SVA VM"
                    } else {
                        throw "Unable to start the SVA VM ($TargetDeviceName)"
                    }
                                
                    # Sleep for 10 seconds before trying again                 
                    Start-Sleep -s $SLEEPTIMEOUT
                    $RetryCount += 1   
                }
            }
            
            $TotalTimeoutPeriod = 0
            while($true)
            {
                Start-Sleep -s $SLEEPTIMEOUT
                try {
                    #Check whether SVA VM is ready or not
                    $SVA = [Microsoft.Azure.Management.StorSimple8000Series.DevicesOperationsExtensions]::Get($StorSimpleClient.Devices, $TargetDeviceName, $ResourceGroupName, $ManagerName)
                } catch {
                    Write-Error -Message $_.Exception
                    throw $_.Exception
                }                
                if($SVA.Status -eq "Online") {
                    Write-Output "SVA ($TargetDeviceName) status is online now"
                    break
                }
                
                $TotalTimeoutPeriod += $SLEEPTIMEOUT
                if ($TotalTimeoutPeriod -gt 600) { #10 minutes
                    throw "Unable to bring SVA ($TargetDeviceName) online"
                }
            }
        }
        else 
        {
            Write-Output "SVA ($TargetDeviceName) is $($TargetDevice.Status)"
        }

        If ($StorSimpleClient -ne $null -and $StorSimpleClient -is [System.IDisposable]) {
            $StorSimpleClient.Dispose()
        }
    }
}