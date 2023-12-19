$ErrorActionPreference = "Stop"

#------------------------------------------------------------------------------#

function WslWrap
{
    # Runs a command using WSL, and returns the stdout as a string array.
    # WSL is executed in Unicode mode (for native commands) unless the -utf8
    # flag is given (for commands running inside of WSL). Throws an exception
    # if the command fails.

    param (
        [switch] $nocheck,
        [switch] $utf8
    )

    $Args = $args
    $encoding = [Console]::OutputEncoding

    if ($utf8) {
        [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
    } else {
        [console]::OutputEncoding = New-Object System.Text.UnicodeEncoding
    }

    $wslOutput = wsl @Args
    $exit_ok = $?
    [Console]::OutputEncoding = $encoding

    if ($exit_ok -or $nocheck) {
        return ,@($wslOutput)
    }

    Write-Error ($wslOutput -join "`r`n")
    $errorMsg = "WSL command failed with arguments: $Args.`nExit Code: $LASTEXITCODE"
    throw $errorMsg
}

function WslDistroInstalled
{
    # Returns true if $Distro is currently installed in WSL.

    param (
        [Parameter(Position=0, Mandatory=$true)]
        [string] $Distro
    )

    $wslOutput = WslWrap -nocheck --list
    $escapedDistro = [regex]::Escape($Distro)

    foreach ($line in $wslOutput) {
        $line = $line.trim()
        if ($line -match "(?i)^$escapedDistro([ ]*[(]default[)])?$") {
           return $true
        }
    }

    return $false
}

function WslCheckActive
{
    # Returns True if WSL is active, or false otherwise. Can optionally
    # specify a distro.

    param (
        [string] $Distro = $null
    )

    $wslOutput = WslWrap -nocheck --list --running
    if (-not [string]::IsNullOrEmpty($Distro)) {
        $escapedDistro = [regex]::Escape($Distro)
        foreach ($line in $wslOutput) {
            $line = $line.trim()

            if ($line -match "(?i)^$escapedDistro( .*$|$)") {
                return $true
            }
        }

        return $false
    }

    return ($wslOutput.Length -gt 1)
}

function WslStop
{
    # Sends a shutdown command and waits until the distro shuts off.

    param (
        [string] $Distro = $null
    )

    while ((WslCheckActive -Distro $Distro)) {
        if (-not [string]::IsNullOrEmpty($Distro)) {
            wsl --terminate $Distro
        } else {
            wsl --shutdown
        }

        Start-Sleep -Seconds 0.25
    }

    Start-Sleep -Seconds 0.5
}

#------------------------------------------------------------------------------#

$target_distro = "Ubuntu-22.04"
$installer = "ubuntu2204"
try {
    Write-Host (WslWrap --set-default-version 2)
    Write-Host (WslWrap --update --web-download)
    wsl --install $target_distro --web-download --no-launch

    if (WslDistroInstalled $target_distro) {
        Write-Host "Removing previous $target_distro installation."
        WslStop $target_distro
        WslWrap --unregister $target_distro
    }

    Invoke-Expression "$installer install --root"

    WslStop
    WslWrap --manage $target_distro --set-sparse true
    WslWrap -utf8 -d $target_distro sh -c "echo WSL Booted OK"

    $ubuntu_mirror = "https://mirrors.edge.kernel.org/ubuntu/pool"
    $cntlm_url = "$ubuntu_mirror/universe/c/cntlm/cntlm_0.92.3-1.2_amd64.deb"
    $cntlm_deb = $cntlm_url -replace ".*/",""
    $proxy = ([System.Net.WebRequest]::GetSystemWebproxy()).GetProxy($cntlm_url)
    Invoke-WebRequest $cntlm_url -Proxy $proxy -ProxyUseDefaultCredentials  -OutFile "$cntlm_deb"

    Write-Host "Copying config folder to WSL installation."
    Copy-Item -Recurse (pwd) -Destination "\\wsl.localhost\$target_distro\root"

    wsl -d $target_distro -u root chmod 0755 /root/wsl-setup/install-cntlm.sh
    wsl -d $target_distro -u root /root/wsl-setup/install-cntlm.sh `
        -p 5F3FA80FA924D4C6FF37D8BB6B297460 `
        install /root/wsl-setup/cntlm_0.92.3-1.2_amd64.deb
    wsl -d $target_distro -u root sh -l -c "apt update"
    wsl -d $target_distro -u root sh -l -c "apt install -y make git python3-venv"
    wsl -d $target_distro -u root sh -l -c "cd /root && make -C wsl-setup run-wsl_config"
    Write-Host "WSL installation configured OK. Script is complete."
} catch {
    Write-Host "-----------"
    $_.ScriptStackTrace
    Write-Host $_
    Read-Host -Prompt "Press Enter to exit"
    throw $_
}

Read-Host -Prompt "Press Enter to exit"
exit
#------------------------------------------------------------------------------#
