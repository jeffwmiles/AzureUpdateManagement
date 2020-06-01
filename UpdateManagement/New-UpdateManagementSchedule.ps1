
# API Reference: https://docs.microsoft.com/en-us/rest/api/automation/softwareupdateconfigurations/create#updateconfiguration
param(
    [parameter(Mandatory = $false)]
    [string]$timeZoneCode,
    [parameter(Mandatory = $false)]
    [string]$timeZoneName,
    [parameter(Mandatory = $false)]
    [DateTime]$PatchTuesday
)

# Calculate the Wednesday and Thursday immediately following Patch Tuesday
$WedDate = $PatchTuesday.AddDays(1).ToString("yyyy-MM-dd")
$ThurDate = $PatchTuesday.AddDays(2).ToString("yyyy-MM-dd")

$UpdateDeployments =
@(
    # Define the update deployments we want (per time zone) based on the tags associated to VMs
    [pscustomobject]@{  deploymentName = "SUG_Wed-8pm-$($timeZoneCode)"; MaintenanceWindow = "Wed-8pm-$($timeZoneCode)"; timezone = $timeZoneName; starttime = "$($WedDate)T20:00:00+00:00"; duration = "PT3H0M" },
    [pscustomobject]@{  deploymentName = "SUG_Wed-10pm-$($timeZoneCode)"; MaintenanceWindow = "Wed-10pm-$($timeZoneCode)"; timezone = $timeZoneName; starttime = "$($WedDate)T22:00:00+00:00"; duration = "PT3H0M" },
    [pscustomobject]@{  deploymentName = "SUG_Thur-12am-$($timeZoneCode)"; MaintenanceWindow = "Thur-12am-$($timeZoneCode)"; timezone = $timeZoneName; starttime = "$($ThurDate)T00:00:00+00:00"; duration = "PT3H0M" },
    [pscustomobject]@{  deploymentName = "SUG_Thur-1am-$($timeZoneCode)"; MaintenanceWindow = "Thur-1am-$($timeZoneCode)"; timezone = $timeZoneName; starttime = "$($ThurDate)T01:00:00+00:00"; duration = "PT3H0M" },
    [pscustomobject]@{  deploymentName = "SUG_Thur-2am-$($timeZoneCode)"; MaintenanceWindow = "Thur-2am-$($timeZoneCode)"; timezone = $timeZoneName; starttime = "$($ThurDate)T02:00:00+00:00"; duration = "PT3H0M" }
)

# Static Schedule Parameters, because they rarely change in my used environment
$AutomationRG = "automation-rg" # Resource Group the Automation Account resides in
$automationAccountName = "automation-acct"
$automationSubscription = "INSERT SUBSCRIPTION ID" # Subscription that the Automation Account resides in
$azureTenantID = "INSERT TENANT ID"

# Assume Az context is already established from calling script
Select-AzSubscription -Subscription "$automationSubscription"

# Get the access token from a cached PowerShell session
    . .\Get-AzCachedAccessToken.ps1
$BearerToken = ('Bearer {0}' -f (Get-AzCachedAccessToken))

# Get all the subscriptions associated with the Azure tenant
$subscriptions = Get-AzSubscription -TenantID $azureTenantID

# Populate this array with the subscription IDs that it should apply to
$scopeDefinition = $subscriptions.SubscriptionID | ForEach-Object { "/subscriptions/$_" }
  # Will look like this:
  #  "/subscriptions/<subid>"
  #  , "/subscriptions/<subid>"

foreach ($updatedeploy in $UpdateDeployments) {
    ### Monthly Parameters ###
    $deploymentName = $updatedeploy.deploymentName
    $starttime = $updatedeploy.starttime

    # Populate this Hashtable with the tags and tag values that should it should be applied to
    $tagdefinition = @{
        MaintenanceWindow = @("$($updatedeploy.MaintenanceWindow)")
    }
    $duration = $updatedeploy.duration # This equals maintenance window - Put in the format PT2H0M, changing the numbers for hours and minutes
    $timeZone = $updatedeploy.timezone
    $rebootSetting = "IfRequired" # Options are Never, IfRequired
    $includedUpdateClassifications = "Critical,UpdateRollup,Security,Updates" # List of options here: https://docs.microsoft.com/en-us/rest/api/automation/softwareupdateconfigurations/create#windowsupdateclasses
    $frequency = "OneTime" # Valid values: https://docs.microsoft.com/en-us/rest/api/automation/softwareupdateconfigurations/create#schedulefrequency
    $interval = "1" # How often to recur based on the frequency (i.e. if frequency = hourly, and interval = 2, then its every 2 hours)

    ### These values below shouldn't need to change
    $applyResourceGroup = $scopeDefinition | ConvertTo-JSON
    $applyTags = $tagdefinition | ConvertTo-JSON

    $RequestHeader = @{
        "Content-Type"  = "application/json";
        "Authorization" = "$BearerToken"
    }

    # JSON formatting to define our required settings
    $Body = @"
{
  "properties": {
    "updateConfiguration": {
	  "operatingSystem": "Windows",
      "duration": "$duration",
      "windows": {
        "excludedKbNumbers": [],
        "includedUpdateClassifications": "$includedUpdateClassifications",
        "rebootSetting": "$rebootSetting"
      },
      "azureVirtualMachines": [],
      "targets":
        {
          "azureQueries": [{
                    "scope": $applyResourceGroup,
                    "tagSettings": {
                        "tags": $applyTags,
                        "filterOperator": "Any"
                    },
                    "locations": null
                }]
        }
    },
    "scheduleInfo": {
      "frequency": "$frequency",
      "startTime": "$starttime",
      "timeZone": "$timeZone",
      "interval": $interval,
	  "isEnabled": true
    }
  }
}
"@

    # Build the URI string to call with a PUT
    $URI = "https://management.azure.com/subscriptions/$($automationSubscription)/" `
        + "resourceGroups/$($AutomationRG)/providers/Microsoft.Automation/" `
        + "automationAccounts/$($automationaccountname)/softwareUpdateConfigurations/$($deploymentName)?api-version=2017-05-15-preview"

    # use the API to add the deployment
    $Response = Invoke-RestMethod -Uri $URI -Method Put -body $body -header $RequestHeader

  # We are adding in Linux VMs, on the Thursday 12am interval
  # As such, run it again once if we match on that iteration in the update job loop
  if ($updatedeploy.deploymentName -like "SUG_Thur-12am*")
    {
      # We're going to use most of the same parameters, but modify a couple for classifications, and the body (to set operating system to Linux)
      $includedUpdateClassifications = "Critical, Security, Other" # List of options here: https://docs.microsoft.com/en-us/rest/api/automation/softwareupdateconfigurations/create#windowsupdateclasses
      $deploymentNameLinux = "$($updatedeploy.deploymentName)_L" # Need a unique Deployment name, so append L to the end to signify linux
    $Body = @"
{
  "properties": {
    "updateConfiguration": {
	  "operatingSystem": "Linux",
      "duration": "$duration",
      "windows": null,
      "linux": {
        "includedPackageClassifications": "$includedUpdateClassifications",
        "excludedPackageNameMasks": [],
        "includedPackageNameMasks": [],
        "rebootSetting": "$rebootSetting",
        "IsInvalidPackageNameMasks": false
      },
      "azureVirtualMachines": [],
      "targets":
        {
          "azureQueries": [{
                    "scope": $applyResourceGroup,
                    "tagSettings": {
                        "tags": $applyTags,
                        "filterOperator": "Any"
                    },
                    "locations": null
                }]
        }
    },
    "scheduleInfo": {
      "frequency": "$frequency",
      "startTime": "$starttime",
      "timeZone": "$timeZone",
      "interval": $interval,
	  "isEnabled": true
    }
  }
}
"@

    # Build the URI string to call with a PUT
    $URI = "https://management.azure.com/subscriptions/$($automationSubscription)/" `
      + "resourceGroups/$($AutomationRG)/providers/Microsoft.Automation/" `
      + "automationAccounts/$($automationaccountname)/softwareUpdateConfigurations/$($deploymentNameLinux)?api-version=2017-05-15-preview"

    # use the API to add the deployment
    $Response = Invoke-RestMethod -Uri $URI -Method Put -body $body -header $RequestHeader
    }
}