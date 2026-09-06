<#
  Build a ready VPN config from the shared template.

    $env:VPN_HOST='...'; $env:VPN_PORT='...'; $env:VPN_PASSWORD='...'
    .\bootstrap.ps1

  Required : VPN_HOST, VPN_PORT, VPN_PASSWORD
  Optional : VPN_SNI (www.bing.com), VPN_INSECURE (true),
             VPN_LISTEN_ADDR (127.0.0.1), VPN_LISTEN_PORT (11080),
             VPN_PROFILE (agent | karing), VPN_OUT (.\vpn-config.json)
#>
$ErrorActionPreference = 'Stop'

$base = 'https://raw.githubusercontent.com/compas-psy/vpn/claude/vpn-server-karing-config-4hjw9e'

function Need($name) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if (-not $value) { throw "$name is required" }
  return $value
}
function Opt($name, $fallback) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if ($value) { return $value } else { return $fallback }
}

$vpnHost   = Need 'VPN_HOST'
$port      = [int](Need 'VPN_PORT')
$password  = Need 'VPN_PASSWORD'
$sni       = Opt 'VPN_SNI' 'www.bing.com'
$insecure  = (Opt 'VPN_INSECURE' 'true').ToLower() -in @('1', 'true', 'yes')
$listen    = Opt 'VPN_LISTEN_ADDR' '127.0.0.1'
$listenPort= [int](Opt 'VPN_LISTEN_PORT' '11080')
$profile   = Opt 'VPN_PROFILE' 'agent'
$out       = Opt 'VPN_OUT' (Join-Path (Get-Location) 'vpn-config.json')

switch ($profile) {
  'agent'  { $url = "$base/agent/singbox-agent-proxy.json" }
  'karing' { $url = "$base/karing/karing-hysteria2-ru-direct.json" }
  default  { throw "VPN_PROFILE must be 'agent' or 'karing'" }
}

$cfg = (Invoke-WebRequest -UseBasicParsing $url).Content | ConvertFrom-Json

foreach ($outbound in $cfg.outbounds) {
  if ($outbound.tag -ne 'proxy') { continue }
  $outbound.server      = $vpnHost
  $outbound.server_port = $port
  $outbound.password    = $password
  $outbound.tls.server_name = $sni
  $outbound.tls.insecure    = $insecure
}

foreach ($inbound in $cfg.inbounds) {
  if ($inbound.tag -eq 'agent-in') {
    $inbound.listen      = $listen
    $inbound.listen_port = $listenPort
  }
}

# the server's own name must resolve outside the tunnel
foreach ($rule in $cfg.dns.rules) {
  if ($rule.PSObject.Properties.Name -contains 'domain' -and $rule.domain -contains '__SERVER__') {
    $rule.domain = @($vpnHost)
  }
}

$json = $cfg | ConvertTo-Json -Depth 32
[IO.File]::WriteAllText($out, $json, (New-Object Text.UTF8Encoding $false))

"wrote $out (profile: $profile)"
if ($profile -eq 'agent') {
  "run: sing-box run -c $out"
  "use: `$env:ALL_PROXY = 'socks5h://${listen}:${listenPort}'"
}
