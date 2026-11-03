param(
    [Parameter(Mandatory = $true)]
    [string]$JSONFile
)

Import-Module ActiveDirectory -ErrorAction Stop

# Load JSON configuration
$json = Get-Content -Path $JSONFile -Raw | ConvertFrom-Json
$Global:Domain = $json.domain

function CreateADGroup()
{
    param(
        [Parameter(Mandatory = $true)]
        $groupObject
    )

    $name = $groupObject.name

    # Create AD group
    try
    {
        New-ADGroup -Name $name -GroupScope Global -ErrorAction Stop
        Write-Host "Created group: $name"
    }
    catch
    {
        Write-Warning "Could not create group '$name': $_"
    }
}

function RemoveADGroup()
{
    param( [Parameter(Mandatory=$true)] $groupObject )

    $name = $groupObject.name
    Remove-ADGroup -Identity $name -Confirm:$False
}

function CreateADUser()
{
    param(
        [Parameter(Mandatory = $true)]
        $userObject
    )

    # Pull name and password from JSON object
    $name = $userObject.name
    $password = $userObject.password

    # Split full name into first name and last name
    $firstname, $lastname = $name.Split(" ", 2)

    # Generate username: first initial + last name
    $username = ($firstname[0] + $lastname).ToLower()

    $samAccountName = $username
    $principalName = "$username@$Global:Domain"

    # Create AD user
    try
    {
        New-ADUser -Name $name -GivenName $firstname -Surname $lastname -SamAccountName $samAccountName -UserPrincipalName $principalName -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) -Enabled $true -ErrorAction Stop

        Write-Host "Created user: $username"
    }
    catch
    {
        Write-Warning "Could not create user '$name': $_"
        return
    }

    # Add user to groups
    foreach ($group_name in $userObject.groups)
    {
        try
        {
            Get-ADGroup -Identity $group_name -ErrorAction Stop |
                Out-Null

            Add-ADGroupMember -Identity $group_name -Members $samAccountName -ErrorAction Stop

            Write-Host "Added '$username' to '$group_name'"
        }
        catch
        {
            Write-Warning "Could not add '$username' to '$group_name': $_"
        }
    }
}

function RemoveADUser(){
    param( [Parameter(Mandatory=$true)] $userObject )

    $name = $userObject.name
    $firstname, $lastname = $name.Split(" ")
    $username = ($firstname[0] + $lastname).ToLower()
    $samAccountName = $username
    Remove-ADUser -Identity $samAccountName -Confirm:$False
}

function WeakenPasswordPolicy(){
    secedit /export /cfg C:\Windows\Tasks\secpol.cfg
    (Get-Content C:\Windows\Tasks\secpol.cfg).replace("PasswordComplexity = 1", "PasswordComplexity = 0").replace("MinimumPasswordLength = 7", "MinimumPasswordLength = 1") | Out-File C:\Windows\Tasks\secpol.cfg
    secedit /configure /db c:\windows\security\local.sdb /cfg C:\Windows\Tasks\secpol.cfg /areas SECURITYPOLICY
    rm -force C:\Windows\Tasks\secpol.cfg -confirm:$false
}

WeakenPasswordPolicy

# Create groups
foreach ($group in $json.groups)
{
    CreateADGroup $group
}

# Create users
foreach ($user in $json.users)
{
    CreateADUser $user
}
