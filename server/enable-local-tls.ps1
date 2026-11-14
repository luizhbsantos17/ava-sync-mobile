$ErrorActionPreference = 'Stop'
$ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Wi-Fi' -ErrorAction Stop |
  Where-Object { $_.IPAddress -notlike '169.254*' -and $_.IPAddress -ne '127.0.0.1' } |
  Select-Object -First 1 -ExpandProperty IPAddress
if (-not $ip) { throw 'Não encontrei um endereço IPv4 ativo na interface Wi-Fi.' }

$directory = Join-Path $PSScriptRoot 'tls'
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
$request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
  'CN=AVA Sync Social Local',
  $rsa,
  [System.Security.Cryptography.HashAlgorithmName]::SHA256,
  [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)
$san = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
$san.AddIpAddress([System.Net.IPAddress]::Parse($ip))
$san.AddDnsName('localhost')
$request.CertificateExtensions.Add($san.Build())
$request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true))
$request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
  [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature,
  $true
))
$certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddYears(2))
$certBytes = [Convert]::ToBase64String($certificate.RawData, [Base64FormattingOptions]::InsertLineBreaks)
$privateBytes = [Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey(), [Base64FormattingOptions]::InsertLineBreaks)
$certPem = "-----BEGIN CERTIFICATE-----`n$certBytes`n-----END CERTIFICATE-----`n"
$privatePem = "-----BEGIN PRIVATE KEY-----`n$privateBytes`n-----END PRIVATE KEY-----`n"
[IO.File]::WriteAllText((Join-Path $directory 'server-cert.pem'), $certPem, [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $directory 'server-key.pem'), $privatePem, [Text.Encoding]::ASCII)

$config = [ordered]@{
  SOCIAL_BACKEND = 'pc'
  SOCIAL_SERVER_URL = "https://${ip}:8787"
  SOCIAL_TLS_CERT_BASE64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($certPem))
}
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'social-config.json'
[IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Output "Certificado HTTPS criado para $ip."
Write-Output "Configuração de build local salva em $configPath (arquivo ignorado pelo Git)."
Write-Output 'O certificado inclui uma chave privada; não compartilhe a pasta server/tls.'
