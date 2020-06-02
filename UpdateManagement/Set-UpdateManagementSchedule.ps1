
# This script is used to deploy UpdateManagement schedules.
param(
    [parameter(Mandatory = $false)]
    [string]$resourceGroupName = "automation-rg", # Resource Group the Automation Account resides in
    [parameter(Mandatory = $false)]
    [string]$automationAccountName = "automation-acct",
    [parameter(Mandatory = $false)]
    [DateTime]$automationSubscription = "INSERT SUBSCRIPTION ID" # Subscription that the Automation Account resides in
)

#Perform the initial login to Azure, using Automation RunAs Account
$connectionName = "AzureRunAsConnection"
try {
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | out-null
}
catch {
    if (!$servicePrincipalConnection) {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Select-AzSubscription -Subscription "$automationSubscription"
# Logic of date calculation from here: https://www.madwithpowershell.com/2014/10/calculating-patch-tuesday-with.html
# Find the 12th day of the month
$BaseDate = ( Get-Date -Day 12 ).Date
# 2 is the Tuesday date of week integer. Subtract the day of week of the 12th to find the difference for AddDays.
# Since we run on the first of the month, assume that this will be the date we use
$PatchTuesday = $BaseDate.AddDays( 2 - [int]$BaseDate.DayOfWeek )

# Just in case running out of normal schedule or on the Patch Tuesday itself
if ( (Get-Date).Date -gt $PatchTuesday ) {
    # if today is greater than patch tuesday for the month
    # get next months' date
    $BaseDate = $BaseDate.AddMonths( 1 )
    $PatchTuesday = $BaseDate.AddDays( 2 - [int]$BaseDate.DayOfWeek )
}

$UsedTimeZones =
@(
    [pscustomobject]@{  timeZoneCode = "AST"; timeZoneName = "America/Halifax" },
    [pscustomobject]@{  timeZoneCode = "EST"; timeZoneName = "America/New_York" }
)
# List of options:
# Desired Time Zone == value to enter
# Atlantic Standard Time  == "America/Halifax"
# Eastern Standard Time   == "America/New_York"
# Pacific Standard Time   == "America/Los_Angeles"
# Central Standard Time   == "America/Chicago"
# MST (Phoenix)           == "America/Phoenix"
# MST (Denver/Edmonton)   == "America/Denver"
# Alaska                  == "America/Anchorage"
# Hawaii                  == "Pacific/Honolulu"

# For each object in our $UsedTimeZones, call the Function
# Use $PatchTuesday - function will automatically calculate the Offset
foreach ($tz in $UsedTimeZones) {
    .\New-UpdateManagementSchedule.ps1 -timeZoneCode $tz.timeZoneCode -timeZoneName $tz.timeZoneName -PatchTuesday $PatchTuesday
}

# Test for the expected output (that there is a next time value scheduled)
    # Get scehdules, check next, validate not none
# If not, send an email to InfrastructureTeam
# Wait at least 30 seconds, because we need to ensure the Next Date gets provisioned properly
Start-Sleep -Seconds 30

$sugs = Get-AzAutomationSoftwareUpdateConfiguration -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName |
    where-object { $_.Name -like "SUG_*" -and $_.ScheduleConfiguration.NextRun -eq $null }

if ($sugs.count -gt 0)
{
    # Send email, because ScheduleConfgiguration.NextRun of a SUG schedule is null
    $Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
</style>
"@
    $EmailCollection = @("This email contains output from an Azure Automation Runbook which schedules Monthly Updates. The table below lists Scheduled Runs that have no Next Date. This implies the Automation Runbook 'Set-UpdateManagementSchedule' failed in some way. <br /><br /> ---------------------------------------------------------------------- <br />")
    $EmailCollection += $sugs | Select-Object Name | ConvertTo-Html -Head $Header
    $EmailCollection = $EmailCollection | out-string
    $emailparameters = @{
        EmailTo = "email@domain.com"
        Body = $EmailCollection | out-string
        Subject = "Azure Update Management - Schedule Creation Failed"
    }
    .\New-EmailDelivery.ps1 @emailparameters
}