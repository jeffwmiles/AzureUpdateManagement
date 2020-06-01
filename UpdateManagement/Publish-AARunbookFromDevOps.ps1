# This script is called from an Azure DevOps Pipeline
    # This script is limited in it's functionality:
    # - It is hard-coded for a schedule of the first day of every month (if a scheduleName is provided)
    # - It only works for runbooks that accept no parameters when linked to a schedule

param (
    [string]$resourceGroupName = "automation-rg",
    [string]$automationAccountName = "automation-acct",
    [string]$sharedsubscription = "INSERT SUBSCRIPTION ID",
    [string]$runbookname,
    [string]$runbookfile,
    [string]$scheduleName
)
# Assume being run in a pipeline with task AzurePowerShell, so we don't worry about context creation.
Select-AzSubscription -SubscriptionId $sharedsubscription

#Check for automation account, otherwise exit
$aatest = Get-AzAutomationAccount -resourceGroupName $resourceGroupName -Name $automationAccountName -ErrorAction Ignore
if (-not $aatest) {
    Write-Host "$automationAccountName does not yet exist." -ForegroundColor "Red"
    Exit
}
else {
    Write-Host "$automationAccountName exists already."
}

#Don't need to check whether Runbook exists in automation account, because we're going to force it all the same.
Write-Host "Importing automation runbook $runbookname" -ForegroundColor "Green"
Import-AzAutomationRunbook -Name $runbookname -Path ".\$runbookfile" -Type PowerShell -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Force -ErrorAction Stop

Write-Host "Publishing automation runbook $runbookname" -ForegroundColor "Green"
Publish-AzAutomationRunbook -Name $runbookname -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -ErrorAction Stop

if ($scheduleName) {
    # Check for schedules, and remove (this will remove unlinked schedule too)
    # If this parameter wasn't provided, assume we don't have a schedule
    Write-Host "$($object.name) - Checking schedule, runbook link, and parameters"
        $sched = Get-AzAutomationSchedule -Name "$scheduleName" -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName -ErrorAction Ignore
        if ($sched) {
            $sched | Remove-AzAutomationSchedule -Force
        }
    # Create Schedule
    $Time = [datetime]"11:00:00"
    $StartTime = $Time.AddDays(1) # Start the schedule at 11am the next day (means catch the next 1st day of month)
    $ScheduleParams = @{
        Name = $scheduleName
        StartTime = $StartTime
        Description = "Will trigger first day of every month"
        DaysOfMonth = "One"
        MonthInterval = 1
        TimeZone = "America/Denver"
        ResourceGroupName = $resourceGroupName
        AutomationAccountName = $automationAccountName
    }
    New-AzAutomationSchedule @ScheduleParams

    # Link runbook to schedule
    # Add parameters as a hash table of key/value pairs
    Write-Host " - Linking $runbookname with schedule for $scheduleName" -ForegroundColor "Green"
    Register-AzAutomationScheduledRunbook -Name $runbookname -ScheduleName "$scheduleName" -AutomationAccountName $automationAccountName -ResourceGroupName $resourceGroupName

}


