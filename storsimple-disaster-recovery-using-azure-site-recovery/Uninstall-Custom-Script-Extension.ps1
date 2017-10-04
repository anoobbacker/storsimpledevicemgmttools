<#
.DESCRIPTION
    This runbook uninstalls the Custom Script Extension from the Azure VMs (brought up after a failover)
    This is required so that after a failover -> failback -> failover, the Custom Script Extension can trigger the iSCSI script
     
.ASSETS (The following need to be stored as Automation Assets) 
    [You can choose to encrypt these assets]
    
    The following have to be added with the Recovery Plan Name as a prefix, eg - TestPlan-StorSimRegKey [where TestPlan is the name of the recovery plan]
    [All these are String variables]
    
    'RecoveryPlanName'-VMGUIDS: 
        	Upon protecting a VM, ASR assigns every VM a unique ID which gives the details of the failed over VM. 
        	Copy it from the Protected Item -> Protection Groups -> Machines -> Properties in the Recovery Services tab.
        	In case of multiple VMs then add them as a comma separated string
#>

workflow Uninstall-Custom-Script-Extension
{  
    Param 
    ( 
        [parameter(Mandatory=$true)] 
        [Object]
        $RecoveryPlanContext
    )
    
    $PlanName = $RecoveryPlanContext.RecoveryPlanName
    
    $VMGUIDString = Get-AutomationVariable -Name "$PlanName-VMGUIDS" 
    if ($VMGUIDString -eq $null) 
    { 
        throw "The VMGUIDs asset has not been created in the Automation service."  
    }
    $VMGUIDs =  $VMGUIDString.Split(",").Trim()
    
    $SLEEPTIMEOUT = 10 #Value in seconds
    $ConnectionName = "AzureRunAsConnection"

    try
    {
        Write-Output "Connecting to Azure"
        # Get the connection "AzureRunAsConnection"
        $ServicePrincipalConnection = Get-AutomationConnection -Name $ConnectionName

        # Get the SubscriptionId, TenantId & ApplicationId
        $SubscriptionId = $ServicePrincipalConnection.SubscriptionId
        $TenantId = $ServicePrincipalConnection.TenantId
        $ClientId = $ServicePrincipalConnection.ApplicationId

        $AzureRmAccount = Add-AzureRmAccount `
                            -ServicePrincipal `
                            -TenantId $using:ServicePrincipalConnection.TenantId `
                            -ApplicationId $using:ServicePrincipalConnection.ApplicationId `
                            -CertificateThumbprint $using:ServicePrincipalConnection.CertificateThumbprint
        
        if ($AzureRmAccount -eq $null) {
            throw "Unable to connect Azure"
        }
    }
    catch {
        if (!$ServicePrincipalConnection) {
            throw "Connection $ConnectionName not found."
        } else {
            throw $_.Exception
        }
    }

    InlineScript 
    {
        $RecoveryPlanContext = $Using:RecoveryPlanContext
        $VMGUIDs = $Using:VMGUIDs
        $SLEEPTIMEOUT = $Using:SLEEPTIMEOUT

        foreach  ($VMGUID in $VMGUIDs)
        { 
            #Fetch VM Details 
            $VMContext = $RecoveryPlanContext.VmMap.$VMGUID    
            if ($VMContext -eq $null) {
                throw "The VM corresponding to the VMGUID - $VMGUID is not included in the Recovery Plan"
            } 

            $VMRoleName =  $VMContext.RoleName 
            if ($VMRoleName -eq $null) {
                throw "Role name is null for VMGUID - $VMGUID"
            }

            $VMResourceGroupName = $VMContext.ResourceGroupName       
            if ($VMResourceGroupName -eq $null) {
                throw "Service name is null for VMGUID - $VMGUID"    
            }
        }
        
        $AzureVM = Get-AzureRmVM -Name $VMRoleName -ResourceGroupName $VMResourceGroupName
        if ($AzureVM -eq $null) {
            throw "Unable to fetch details of Azure VM - $VMRoleName"
        }
        
        Write-Output "Uninstalling custom script extension on $VMRoleName" 
        try {
            $result = Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $VMResourceGroupName -VMName $VMRoleName -Name "CustomScriptExtension" -Force
        } catch {
            throw "Unable to uninstall custom script extension - $VMRoleName"
        }
    }
}
