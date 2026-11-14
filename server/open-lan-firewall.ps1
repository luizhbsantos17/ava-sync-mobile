$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $admin) { throw 'Abra o PowerShell como Administrador e execute este script novamente.' }

$ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi' -ErrorAction Stop |
  Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
  Select-Object -First 1 -ExpandProperty IPAddress
if (-not $ip) { throw 'Não encontrei um endereço IPv4 ativo na interface Wi-Fi.' }

Get-NetFirewallRule -DisplayName 'AVA Sync Social LAN' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'AVA Sync Social LAN' -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort 8787 -LocalAddress $ip -RemoteAddress LocalSubnet -Profile Private | Out-Null
Write-Output "Acesso liberado somente para a rede local privada em ${ip}:8787."
