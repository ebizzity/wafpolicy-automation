param ( 
    [object] $WebhookData
)


# // Start Azure Automation Login Using Service Principal
$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#Get Webhook Data 

If ($WebhookData.WebhookName) {
    $WebhookName     =     $WebhookData.WebhookName
    $WebhookHeaders  =     $WebhookData.RequestHeader
    $WebhookBody     =     $WebhookData.RequestBody
} ElseIf ($WebhookData) {
    $WebhookJSON = ConvertFrom-Json -InputObject $WebhookData
    $WebhookName     =     $WebhookJSON.WebhookName
    $WebhookHeaders  =     $WebhookJSON.RequestHeader
    $WebhookBody     =     $WebhookJSON.RequestBody
} Else {
   Write-Error -Message 'Runbook was not started from Webhook' -ErrorAction stop
}

#Convert to PS Object

$json = $WebhookBody | ConvertFrom-Json


#Set variables with information in above json

$rg = $json.data[0].context[0].activityLog.resourceGroupName
$resourceid = $json.data[0].context[0].activityLog.resourceId
$policyname = $resourceid.Substring($resourceid.LastIndexOf('/')+1)
$caller = $json.data[0].context[0].activityLog.caller


#Check to see if trigger of runbook is self-inflicted
if ($caller.contains("@") -ne "True")
{
    Write-Error -Message 'Alert generated from runbook, not a user... Terminating...' -ErrorAction continue
    exit 0
}

Write-Output "Resource Group: $rg"
Write-Output "Checking WAF Policy: $policyname"

$flag = 0

$policy = Get-AzFrontDoorWafPolicy -ResourceGroupName $rg -name $policyname

#Get overrides / Update Overrides

if ($policy.ManagedRules){

    foreach ($rule in $policy.ManagedRules){
        
        foreach ($override in $rule.RuleGroupOverrides){

            if ($override.RuleGroupName -ne "XSS"){  #ignoring changes to XSS Rule Groups as an example

                foreach ($mgdrule in $override.ManagedRuleOverrides){

                    if ($mgdrule.EnabledState -ne "Enabled"){

                        $mgdrule.EnabledState = "Enabled"
                        $flag = 1

                    }

                }


            }

        }

    }

}else{

    Write-Output "Enabling Default Ruleset"
    $policy.ManagedRules =  New-AzFrontDoorWafManagedRuleObject -Type DefaultRuleSet -Version 1.0
    $flag = 1
    


}

# Update only if there are changes to make
if ($flag -eq 1){
    write-output "Writing Changes to Policy..."
    $policy | Update-AzFrontDoorWafPolicy

}else{
 
    write-output "No Changes to make..."

}

