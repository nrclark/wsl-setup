$distro = "Ubuntu-22.04"
$installer = "ubuntu2204"

Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
wsl --update

[console]::OutputEncoding = New-Object System.Text.UnicodeEncoding
$encoding = [Console]::OutputEncoding
$wslOutput = wsl --list
[Console]::OutputEncoding = $encoding 

foreach ($line in $wslOutput) {
    echo $line
    if ($line -like $distro) {
        Write-Host "Removing previous $distro installation."
        wsl --terminate $line
        wsl --unregister $line
        break
    }
}

#------------------------------------------------------------------------------#

Invoke-Expression "$installer install --root"

wsl --shutdown $distro
Start-Sleep -Seconds 5
wsl --manage $distro --set-sparse true

wsl -d $distro -u root apt update
wsl -d $distro -u root apt install -y make git python3-venv
wsl -d $distro -u root sh -c "cd /root && git clone https://github.com/nrclark/wsl-setup.git"
wsl -d $distro -u root sh -c "cd /root && make -C wsl-setup run-wsl_config"

wsl --shutdown $distro
Start-Sleep -Seconds 5
wsl -d $distro rm -rf /root/snap /root/wsl-setup /root/.cache /root/.ansible
wsl -d $distro bash -c "echo Completed OK."

#wsl --install $distro --web-download --no-launch*


#$installer install --root
#cmd.exe /c "wsl --install ubuntu-22.04 --web-download < .\user.txt"

#wsl --install Ubuntu-22.04 --web-download --no-launch

#------------------------------------------------------------------------------#
