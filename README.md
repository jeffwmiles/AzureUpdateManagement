# AzureUpdateManagement
A collection of Azure Automation Runbooks which will facilitate creation of Update Management schedules

## Description
The contents of this repository will produce an Azure DevOps pipeline which can import, publish, and schedule runbooks in an Azure Automation account.
The runbooks will be used on the first of every month, to create Update Management Schedules for the Wednesday after the next Patch Tuesday, based on Time Zones specified and a system of Maintenance Window tags on Virtual Machines.

**Set-UpdateManagementSchedule.ps1** defines time zones, and then iterates over them calling New-UpdateManagementSchedule.ps1 for each. At the end, it uses New-EmailDelivery.ps1 to send results by email to specified SMTP server.

**New-UpdateManagementSchedule.ps1** calls **Get-AzCachedAccessToken.ps1** in order to use an existing Az PowerShell context to create a bearer token and authenticate against Azure REST API with it (where I'm using Update Management endpoints).

**Publish-AARunbookFromDevOps.ps1** is my script that gets called within the DevOps pipeline, to import and publish the runbooks to the automation account.

We want Set-UpdateManagementSchedule.ps1 to run once per month, because it calculates the appropriate timing of Update Management schedules. I don't want any of the other scripts to have a schedule at all, since they're just referenced at some point in time.

## Prerequisites
The following items should exist already, as this code is dependent upon them
- Resource Group
- Automation Account with Update Management configured
    - Virtual Machines with a tag "MaintenanceWindow" and values specified in New-UpdateManagementSchedule.ps1"
- Azure DevOps project
    - Service connection to Azure, with contributor rights over the Automation Account
- (If using SMTP delivery) Automation variable named "SmtpHost" containing the smtp server name
- (If using SMTP delivery) Automation credentials named "SmtpCreds" for authenticating to SMTP server


## Deployment

- Clone this repository and store it within an Azure Repo
    - Modify *Set-UpdateManagementSchedule.ps1*: update parameters at top of file, and "$UsedTimeZones" array part-way through the file
    - Modify *New-UpdateManagementSchedule.ps1*: update array $UpdateDeployments to contain the Maintenance Windows you desire
    - Modify *Publish-AARunbookFromDevOps.ps1*: update parameters at top of file
    - Modify *New-EmailDelivery.ps1*: update parameter for From email address
    - Modify *azure-pipelines.yaml*: update the 'azureSubscription' property on each task, to be the name of your DevOps service connection

- Create a new Azure Pipeline
    - Use the Azure Repo as your source
    - Import from a YAML file, and choose "azure-pipelines.yaml" as the source
    - Rename your pipeline if desired
    - Manually start the pipeline, or make a commit to Master branch for a file within the UpdateManagement folder

## Results
A successful pipeline run will produce:
- 4 runbooks deployed to your Automation Account
- A new Schedule, linked to *Set-UpdateManagementSchedule*, to run on the 1st of the Month

Manually running the *Set-UpdateManagementSchedule* runbook will interact with the Azure REST API for UpdateManagement, and produce new Scheduled deployments based upon the time zones and maintenance windows you specified.
