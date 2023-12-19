$ErrorActionPreference = "Stop"

#------------------------------------------------------------------------------#

function RunOK
{
    # Runs a command-line program and throws an error if the program exits
    # with a nonzero error-code.

    & $args[0] @($args[1..($args.Length - 1)]) | Tee-Object -Variable result

    if ($LASTEXITCODE -ne 0) {
        Write-Host $result
        throw "Error: Command failed with exit code $LASTEXITCODE."
    }
}

function CheckElevated
{
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = (New-Object Security.Principal.WindowsPrincipal $user)
    $admin_role = [Security.Principal.WindowsBuiltinRole]::Administrator
    return $principal.IsInRole($admin_role)
}

function WslGetIp {

    param (
        [string] $Distro = $null
    )

    if ($Distro -ne $null) {
        $result = (RunOK wsl.exe ip address show dev eth0)
    } else {
        $result = (RunOK wsl.exe -d $Distro ip address show dev eth0)
    }

    $result = (RunOK wsl.exe ip address show dev eth0)
    $result = $result | Where-Object {$_.Trim() -ne ""} | ForEach-Object {$_.Trim()}
    $line = $result | Where-Object {$_ -match "^inet[ \t]"}
    ($line | Select-String -Pattern "([0-9]{1,3}[.]){1,3}[0-9]{1,3}").Matches.Value
}

function FindPortFwd {
    $result = @()
    $lines = (RunOK netsh interface portproxy show v4tov4) | `
        Where-Object {$_.Trim() -ne ""} | ForEach-Object {$_.Trim()}
    $lines = @($lines | Where-Object { $_ -match "^[0-9. \t]+$" })

    foreach ($line in $lines) {
        $fields = ($line -split "\s+")
        if ($fields.Length -ne 4) {
            Write-Error "Unexpected number of fields in netsh output."
        }

        $record = @{
            Source=@{
                IP=$fields[0];
                Port=$fields[1];
            };
            Dest=@{
                IP=$fields[2];
                Port=$fields[3];
            };
        }

        $result += $record
    }

    $result
}

function MakePortFwd {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable] $dest,

        [Parameter(Mandatory=$true)]
        [hashtable] $source
    )

   RunOK netsh interface portproxy add v4tov4 `
        listenport=$($source["port"]) listenaddress=$($source["ip"]) `
        connectport=$($dest["port"]) connectaddress=$($dest["ip"])
}

#-----------------------------------------------------------------------------#

if (-not (CheckElevated)) {
    Write-Host "Admin permissions are necessary to run this script."
    Write-Host "Relaunching as administrator."

    $cmd_args=@("-NoProfile", "-NonInteractive",
                "-ExecutionPolicy", "bypass", "-File",
                $MyInvocation.MyCommand.Path, "-ElevatedInstall")

    Start-Process -FilePath "powershell.exe" -Verb RunAs `
        -ArgumentList $cmd_args
    exit
}

try {
    $ip=(WslGetIp -distro "Ubuntu22.04")
    MakePortFwd -source @{ip="0.0.0.0"; port=22} -dest @{ip=$ip; port=22}
    Write-Host "Port forwarded OK. Script is complete."
    Read-Host -Prompt "Press Enter to exit"
} catch {
    Write-Host "-----------"
    $_.ScriptStackTrace
    Write-Host $_
    Read-Host -Prompt "Press Enter to exit"
    throw $_
}


