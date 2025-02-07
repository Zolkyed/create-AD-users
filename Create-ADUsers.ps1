param (
    [switch]$diff,
    [switch]$nodesac,
    [switch]$nomail
)

$csvPath = Read-Host "Veuillez entrer le chemin complet du fichier CSV"
$users = Import-Csv -Path $csvPath
$logFilePath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("Desktop"), "AD_User_Management_Log.txt")

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You need to run this script as Administrator."
    exit
}

$date = Get-Date -Format "yyyyMMdd"
$logSource = "AD_$date"

if (-not (Get-EventLog -LogName Application -ErrorAction SilentlyContinue)) {
    Write-Host "Application event log does not exist or is not accessible." -ForegroundColor Red
    exit
}

try {
    if (-not (Get-EventLog -LogName Application -Source $logSource -ErrorAction Stop)) {
        Write-Host "Log source not found, creating new event log source: $logSource"
        New-EventLog -LogName Application -Source $logSource
    }
}
catch {
    Write-Host "Log source does not exist. Creating a new source: $logSource" -ForegroundColor Yellow
    New-EventLog -LogName Application -Source $logSource
}

function Create-ADUser {
    param (
        [string]$name,   
        [string]$email,
        [string]$phone,
        [string]$age
    )

    $nameParts = $name -split ' '
    $firstName = $nameParts[0]
    $lastName = $nameParts[-1]

    $username = ($firstName.Substring(0, 1) + $lastName).ToLower()

    $existingUser = Get-ADUser -Filter { SamAccountName -eq $username }
    
    $suffix = 1
    while ($existingUser) {
        $username = ($firstName.Substring(0, 1) + $lastName + $suffix).ToLower()
        $existingUser = Get-ADUser -Filter { SamAccountName -eq $username }
        $suffix++
    }

    New-ADUser `
        -Name "$firstName $lastName" `
        -GivenName $firstName `
        -Surname $lastName `
        -SamAccountName $username `
        -UserPrincipalName "$username@infocrosemont.qc.ca" `
        -EmailAddress $email `
        -OfficePhone $phone `
        -Description "Age: $age" `
        -AccountPassword (ConvertTo-SecureString "P@ssw0rd!" -AsPlainText -Force) `
        -PasswordNeverExpires $false `
        -ChangePasswordAtLogon $true `
        -Enabled $true

    Write-Host "User $username created successfully."
    $eventMessage = "User Created: $firstName $lastName ($username)"
    Write-EventLog -LogName Application -Source $logSource -EventId 9945 -EntryType Information -Message $eventMessage

    return $username
}

function Disable-ADUser {
    param (
        [string]$username
    )

    Disable-ADAccount -Identity $username
    Write-Host "User $username disabled."
    $eventMessage = "User Disabled: $username"
    Write-EventLog -LogName Application -Source $logSource -EventId 9946 -EntryType Information -Message $eventMessage
}

function Send-Email {
    param (
        [string]$to,
        [string]$subject,
        [string]$body
    )

    if (-not $to -or $to.Trim() -eq "") {
        return
    }
    $From = "zolkyed@gmail.com"
    $SMTPServer = "smtp.gmail.com"
    $SMTPPort = 587
    $Password = "rfje kltz dsaf fojv " | ConvertTo-SecureString -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $From, $Password

    Send-MailMessage -From $From -To $to -Subject $subject -Body $body -SmtpServer "smtp.gmail.com" -Port 587 -UseSsl -Credential $Credential

    Write-Host "Email sent to $to"
    $eventMessage = "Email sent to $to"
    Write-EventLog -LogName Application -Source $logSource -EventId 9943 -EntryType Information -Message $eventMessage
    Start-Sleep -Seconds 1
}

function Compare-Users {
    param (
        [array]$newUsers,
        [array]$existingUsers
    )

    $toCreate = @()
    $toDisable = @()

    foreach ($user in $newUsers) {
        $username = ($user.name.Split(' ')[0].Substring(0, 1) + $user.name.Split(' ')[-1]).ToLower()
        $exists = $existingUsers | Where-Object { $_.SamAccountName -eq $username }

        if (-not $exists) {
            $toCreate += $user
        }
    }

    foreach ($user in $existingUsers) {
        if (-not ($newUsers | Where-Object { $_.name.Split(' ')[0].Substring(0, 1) + $_.name.Split(' ')[-1] -eq $user.SamAccountName })) {
            $toDisable += $user
        }
    }

    return [pscustomobject]@{
        Create = $toCreate
        Disable = $toDisable
    }
}

$existingUsers = Get-ADUser -Filter * -Property SamAccountName
$comparison = Compare-Users -newUsers $users -existingUsers $existingUsers

if ($diff) {
    $comparison.Create | Export-Csv -Path "to_create.csv" -NoTypeInformation
    $comparison.Disable | Export-Csv -Path "to_disable.csv" -NoTypeInformation
}

if ($nodesac) {
    $comparison.Disable | Export-Csv -Path "should_disable.csv" -NoTypeInformation
} else {
    foreach ($user in $comparison.Disable) {
        Disable-ADUser -username $user.SamAccountName

        if (-not $nomail) {
            $subject = "Désactivation de votre compte"
            $body = "Bonjour $($user.GivenName) $($user.Surname),`n`nVotre compte AD a ete desactive."
            Send-Email -to $user.EmailAddress -subject $subject -body $body
        }
    }
}

foreach ($user in $comparison.Create) {
    $username = Create-ADUser -name $user.name -email $user.email -phone $user.phone -age $user.birthday

    if (-not $nomail) {
        $nameParts = $user.name -split ' '
        $firstName = $nameParts[0]
        $lastName = $nameParts[-1]
        $subject = "Création de votre compte"
        $body = "Bonjour $firstName $lastName,`n`nVotre compte AD a ete cree."
        Send-Email -to $user.email -subject $subject -body $body
    }
}
