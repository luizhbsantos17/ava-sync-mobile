$ErrorActionPreference = 'Stop'
$env:SOCIAL_PORT = '8787'
$tlsKey = Join-Path $PSScriptRoot 'tls\server-key.pem'
$tlsCert = Join-Path $PSScriptRoot 'tls\server-cert.pem'
if ((Test-Path -LiteralPath $tlsKey) -and (Test-Path -LiteralPath $tlsCert)) {
  $wifiIp = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi' -ErrorAction Stop |
    Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
    Select-Object -First 1 -ExpandProperty IPAddress
  if (-not $wifiIp) { throw 'Não encontrei um endereço IPv4 ativo na interface Wi-Fi.' }
  $env:SOCIAL_HOST = $wifiIp
  $env:SOCIAL_TLS_KEY = $tlsKey
  $env:SOCIAL_TLS_CERT = $tlsCert
} else {
  $env:SOCIAL_HOST = '127.0.0.1'
}
node (Join-Path $PSScriptRoot 'index.js')
