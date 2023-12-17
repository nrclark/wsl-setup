$ErrorActionPreference = "Stop"

#------------------------------------------------------------------------------#

function CheckElevated
{  
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = (New-Object Security.Principal.WindowsPrincipal $user)
    $admin_role = [Security.Principal.WindowsBuiltinRole]::Administrator
    return $principal.IsInRole($admin_role)
}

function AskReboot
{
    Write-Host "Press any key to reboot your computer, or CTRL+C to abort."

    while($true) {
        if ([Console]::KeyAvailable) {
            [Console]::ReadKey($true)
            break;
        }
        Start-Sleep -Seconds 0.05
    }

    Restart-Computer
}

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
    Enable-WindowsOptionalFeature -NoRestart -Online `
    -FeatureName "VirtualMachinePlatform"

    Enable-WindowsOptionalFeature -NoRestart -Online `
        -FeatureName "Microsoft-Windows-Subsystem-Linux"

    wsl.exe --install --no-distribution
    wsl.exe --update --web-download
    wsl.exe --set-default-version 2
    Write-Host "WSL feature enabled OK. Script is complete."
    AskReboot
} catch {
    Write-Host "-----------"
    $_.ScriptStackTrace
    Write-Host $_
    Read-Host -Prompt "Press Enter to exit"
    throw $_
} 


