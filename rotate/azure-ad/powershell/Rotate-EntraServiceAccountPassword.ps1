<#
.SYNOPSIS
    Rotates the password for an Entra ID (Azure AD) service account using the
    Microsoft Graph API.

.DESCRIPTION
    Generates a strong random password, acquires a Microsoft Graph access token
    via the client credentials flow, and calls Microsoft Graph to set the new
    password on the specified user.

    The new password is printed to stdout exactly once. Capture it from the
    script's output and store it in your secret manager. The Graph PATCH does
    not echo the password back, so once this script exits the value is gone.

    Reads three env vars for app registration credentials:
        ENTRA_TENANT_ID
        ENTRA_CLIENT_ID
        ENTRA_CLIENT_SECRET

    The app registration must have the Microsoft Graph application permission
    User.ReadWrite.All with admin consent granted.

.PARAMETER UserPrincipalName
    The UPN of the service account to rotate. For example,
    svc-automation@rooez.com.

.PARAMETER PasswordLength
    Length of the generated password. Default 32.

.PARAMETER ForceChangeAtNextSignIn
    If set, the user must change the password at next sign-in. Leave this off
    for service accounts since they have no human to complete the change.

.EXAMPLE
    ./Rotate-EntraServiceAccountPassword.ps1 -UserPrincipalName "svc-ise@rooez.com"

    Rotates the password for svc-ise@rooez.com using a 32-character random
    password.

.EXAMPLE
    ./Rotate-EntraServiceAccountPassword.ps1 -UserPrincipalName "svc-automation@rooez.com" -PasswordLength 64

    Same as above but with a 64-character password.

.NOTES
    Microsoft Graph reference:
    https://learn.microsoft.com/graph/api/user-update
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$UserPrincipalName,

    [Parameter()]
    [ValidateRange(12, 256)]
    [int]$PasswordLength = 32,

    [Parameter()]
    [switch]$ForceChangeAtNextSignIn
)

$ErrorActionPreference = 'Stop'

# Load app registration credentials from the environment so nothing
# sensitive lives in the script itself.
$tenantId     = $env:ENTRA_TENANT_ID
$clientId     = $env:ENTRA_CLIENT_ID
$clientSecret = $env:ENTRA_CLIENT_SECRET

foreach ($pair in @(
        @('ENTRA_TENANT_ID', $tenantId),
        @('ENTRA_CLIENT_ID', $clientId),
        @('ENTRA_CLIENT_SECRET', $clientSecret)
    )) {
    if ([string]::IsNullOrWhiteSpace($pair[1])) {
        Write-Error "Environment variable $($pair[0]) is not set."
        exit 1
    }
}

# Build a strong random password. We deliberately seed it with one of each
# character class and then fill the rest from the pooled set, then shuffle.
# This guarantees the result satisfies "at least one upper, lower, digit,
# special" complexity rules that most identity stores apply.
function New-StrongPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Length
    )

    $upper   = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower   = [char[]]'abcdefghijklmnopqrstuvwxyz'
    $digits  = [char[]]'0123456789'
    # Avoid characters that are awkward in shells, URLs, and JSON: ' " \ ` & ; < > $
    $special = [char[]]'!@#%^*()-_=+[]{}:,.?/'

    $allClasses = $upper + $lower + $digits + $special

    $chars = @(
        ($upper   | Get-Random)
        ($lower   | Get-Random)
        ($digits  | Get-Random)
        ($special | Get-Random)
    )
    while ($chars.Count -lt $Length) {
        $chars += ($allClasses | Get-Random)
    }

    -join ($chars | Sort-Object { Get-Random })
}

# Acquire an access token via the client credentials flow.
# https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow
function Get-GraphAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$ClientSecret
    )

    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
        grant_type    = 'client_credentials'
    }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $response.access_token
    }
    catch {
        Write-Error "Failed to acquire Graph access token: $($_.Exception.Message)"
        throw
    }
}

# Set the password on the target user. Graph returns 204 No Content on
# success, so we don't get a body back to inspect; we trust the absence of
# an exception.
function Set-EntraUserPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][string]$NewPassword,
        [Parameter()][bool]$ForceChange = $false
    )

    $patchUri = "https://graph.microsoft.com/v1.0/users/$UserPrincipalName"
    $body = @{
        passwordProfile = @{
            password                      = $NewPassword
            forceChangePasswordNextSignIn = $ForceChange
        }
    } | ConvertTo-Json -Compress

    $headers = @{
        Authorization  = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
    }

    try {
        Invoke-RestMethod -Method Patch -Uri $patchUri -Headers $headers -Body $body | Out-Null
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Error "User '$UserPrincipalName' not found in this tenant."
        }
        elseif ($statusCode -eq 403) {
            Write-Error "Forbidden. Confirm the app registration has User.ReadWrite.All with admin consent."
        }
        else {
            Write-Error "Graph API error ($statusCode): $($_.Exception.Message)"
        }
        throw
    }
}

# Main flow.
Write-Verbose "Generating new password ($PasswordLength chars)"
$newPassword = New-StrongPassword -Length $PasswordLength

Write-Verbose "Acquiring Graph access token"
$token = Get-GraphAccessToken -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret

Write-Verbose "Setting new password on $UserPrincipalName"
Set-EntraUserPassword `
    -AccessToken $token `
    -UserPrincipalName $UserPrincipalName `
    -NewPassword $newPassword `
    -ForceChange $ForceChangeAtNextSignIn.IsPresent

Write-Host ""
Write-Host "Password rotated for $UserPrincipalName" -ForegroundColor Green
Write-Host "New password: $newPassword"
Write-Host ""
Write-Host "Capture this value now. It will not be displayed again."

exit 0
