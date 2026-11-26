<#
.SYNOPSIS
  Membuat keystore rilis PERMANEN untuk MotorQu Solid (sekali seumur aplikasi).

.DESCRIPTION
  - Membuat android/app/release.jks (PKCS12, RSA 2048, berlaku ~27 tahun).
  - Menulis android/key.properties agar `flutter build apk --release` lokal
    memakai kunci yang sama dengan CI.
  - Menyalin isi keystore (base64) ke clipboard untuk secret GitHub.

  Kedua file di-ignore git. JANGAN commit, dan SIMPAN CADANGANNYA (misal di
  password manager). Jika keystore ini hilang, APK berikutnya tidak bisa
  meng-update aplikasi yang sudah terpasang di HP pengguna.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\create-release-keystore.ps1
#>
param(
  [string]$Alias = 'motorqu-solid',
  [string]$DName = 'CN=MotorQu Solid, O=MotorQu, C=ID'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $repoRoot 'android'
$keystoreDir = Join-Path $androidDir 'app'
$keystorePath = Join-Path $keystoreDir 'release.jks'
$propsPath = Join-Path $androidDir 'key.properties'

if (Test-Path $keystorePath) {
  Write-Error "Keystore sudah ada di $keystorePath. Script dihentikan agar kunci permanen tidak tertimpa."
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if ($null -eq $keytool) {
  Write-Error 'keytool tidak ditemukan. Pasang JDK dan pastikan folder bin-nya ada di PATH.'
}

function ConvertTo-PlainText([Security.SecureString]$secure) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$pw1 = ConvertTo-PlainText (Read-Host 'Password keystore (min. 6 karakter)' -AsSecureString)
$pw2 = ConvertTo-PlainText (Read-Host 'Ulangi password' -AsSecureString)
if ($pw1 -ne $pw2) { Write-Error 'Password tidak sama.' }
if ($pw1.Length -lt 6) { Write-Error 'Password minimal 6 karakter.' }

New-Item -ItemType Directory -Force -Path $keystoreDir | Out-Null

# PKCS12 memakai satu password untuk store dan key.
& $keytool.Source -genkeypair -noprompt `
  -keystore $keystorePath -storetype PKCS12 `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias $Alias -dname $DName `
  -storepass $pw1 -keypass $pw1
if ($LASTEXITCODE -ne 0) { Write-Error 'keytool gagal membuat keystore.' }

# Format .properties Java: backslash harus di-escape. Tulis tanpa BOM.
$escaped = $pw1.Replace('\', '\\')
$props = @(
  'storeFile=release.jks'  # relatif terhadap android/app
  "storePassword=$escaped"
  "keyAlias=$Alias"
  "keyPassword=$escaped"
) -join "`n"
[IO.File]::WriteAllText($propsPath, $props + "`n", (New-Object Text.UTF8Encoding($false)))

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))
Set-Clipboard -Value $base64

Write-Host ''
Write-Host 'Keystore dibuat:' $keystorePath -ForegroundColor Green
Write-Host 'key.properties ditulis:' $propsPath -ForegroundColor Green
Write-Host ''
Write-Host 'Fingerprint sertifikat (catat, harus sama di setiap rilis):'
& $keytool.Source -list -v -keystore $keystorePath -storepass $pw1 -alias $Alias |
  Select-String -Pattern 'SHA256:'
Write-Host ''
Write-Host 'Langkah berikutnya: buka GitHub repo > Settings > Secrets and variables > Actions,' -ForegroundColor Yellow
Write-Host 'lalu buat 4 secret berikut:' -ForegroundColor Yellow
Write-Host '  KEYSTORE_BASE64   = (sudah disalin ke clipboard, tinggal paste)'
Write-Host '  KEYSTORE_PASSWORD = password yang barusan diketik'
Write-Host "  KEY_ALIAS         = $Alias"
Write-Host '  KEY_PASSWORD      = password yang sama'
Write-Host ''
Write-Host 'PENTING: cadangkan release.jks dan password-nya di tempat aman.' -ForegroundColor Red
