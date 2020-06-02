# This is intended to be an azure automation runbook, which can deliver email
# It depends upon Automation resources for:
    # - AutomationVariable -Name 'SmtpHost'
    # - AutomationPSCredential -Name 'PostmarkSMTP'

Param (
        [Parameter(Mandatory=$true)]
        [String[]]$EmailTo,
        [Parameter(Mandatory=$true)]
        [String]$Subject,
        [Parameter(Mandatory=$true)]
        [String]$Body,
        [Parameter(Mandatory=$false)]
        [String]$EmailFrom = 'email@domain.com',
        [parameter(Mandatory=$false)]
        [String] $SmtpServer = (Get-AutomationVariable -Name 'SmtpHost'),
        [parameter(Mandatory=$false)]
        [String] $SmtpUsername,
        [parameter(Mandatory=$false)]
        [SecureString] $SmtpPassword
    )

        $SMTPMessage = New-Object System.Net.Mail.MailMessage($EmailFrom,$EmailTo,$Subject,$Body)
        $SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 587)
        $SMTPMessage.IsBodyHtml = $true
        $SMTPClient.EnableSsl = $true
        $SMTPClient.Credentials = Get-AutomationPSCredential -Name 'SmtpCreds' #New-Object System.Net.NetworkCredential($SmtpUsername, $SmtpPassword);
        $SMTPClient.Send($SMTPMessage)
        Remove-Variable -Name SMTPClient
        Remove-Variable -Name SmtpPassword