function Wait-ForPageReady {
    param(
        [Parameter(Mandatory=$true)]
        [System.Net.WebSockets.ClientWebSocket] $Socket,

        [Parameter(Mandatory=$true)]
        [string] $TargetUrl,

        [int] $MaxRetries = 50,
        [int] $DelayMs = 2000
    )

    $ready = $false
    $attempt = 0

    while (-not $ready) {
        # --- Obtener los contextos de ejecución ---
        $cmdContexts = @'
{"id":500,"method":"Runtime.executionContexts"}
'@
        $bytes = [Text.Encoding]::UTF8.GetBytes($cmdContexts)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)
        $Socket.SendAsync($segment,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).Wait()

        $buffer = New-Object byte[] 16384
        $result = $Socket.ReceiveAsync([ArraySegment[byte]]$buffer,[Threading.CancellationToken]::None).Result
        $json = [Text.Encoding]::UTF8.GetString($buffer,0,$result.Count)
        $contexts = ($json | ConvertFrom-Json).result.executionContexts

        # Elegir un contexto que tenga un frameId (normalmente la página principal)
        $targetContext = $contexts | Where-Object { $_.auxData.frameId -ne $null } | Select-Object -First 1
        if (-not $targetContext) {
            Start-Sleep -Milliseconds 500
            continue
        }
        $contextId = $targetContext.id

        # --- Evaluar URL ---
        $cmdUrl = @"
{"id":501,"method":"Runtime.evaluate","params":{"expression":"window.location.href","contextId":$contextId}}
"@
        $bytes = [Text.Encoding]::UTF8.GetBytes($cmdUrl)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)
        $Socket.SendAsync($segment,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).Wait()

        $buffer = New-Object byte[] 10240
        $result = $Socket.ReceiveAsync([ArraySegment[byte]]$buffer,[Threading.CancellationToken]::None).Result
        $jsonUrl = [Text.Encoding]::UTF8.GetString($buffer,0,$result.Count)
        $currentUrl = ($jsonUrl | ConvertFrom-Json).result.result.value

        # --- Evaluar readyState ---
        $cmdReady = @"
{"id":502,"method":"Runtime.evaluate","params":{"expression":"document.readyState","contextId":$contextId}}
"@
        $bytes = [Text.Encoding]::UTF8.GetBytes($cmdReady)
        $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)
        $Socket.SendAsync($segment,[System.Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).Wait()

        $buffer = New-Object byte[] 10240
        $result = $Socket.ReceiveAsync([ArraySegment[byte]]$buffer,[Threading.CancellationToken]::None).Result
        $jsonReady = [Text.Encoding]::UTF8.GetString($buffer,0,$result.Count)
        $state = ($jsonReady | ConvertFrom-Json).result.result.value

        # --- Verificación final ---
        if ($currentUrl -eq $TargetUrl -and $state -eq "complete") {
            $ready = $true
        } else {
            Start-Sleep -Milliseconds $DelayMs
            $attempt++
            Write-Progress -Activity "Waiting for URL and readyState" -Status "Retry count: $attempt"
            if ($attempt -ge $MaxRetries) {
                Write-Host "Max retries reached. Página no cargó correctamente."
                exit 1
            }
        }
    }

    Write-Host "La página $TargetUrl fue cargada exitosamente"
}

$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$tempProfile = "$env:TEMP\EdgeTempProfile"

# --- Abrir Edge ---
$proc = Start-Process $edge `
    "--remote-debugging-port=9222 --user-data-dir=""$tempProfile"" https://rda.prod.cloud.fedex.com/rda/"

# --- Esperar pestaña RDA ---
$tab = $null
$X = 0
while (-not $tab) {
    try {
        $tabs = Invoke-RestMethod http://localhost:9222/json
        Write-Host "Tabs count:" $tabs.Count
        $tab = $tabs | Where-Object { $_.url -like 'https://rda.prod.cloud.fedex.com/rda/*' } | Select-Object -First 1
        if ($tab) { Write-Host "RDA tab found:" $tab.url }
        else { Write-Host "`rRDA tab not found yet, retrying..." -NoNewline }
    } catch {
        Write-Host "`rDevTools not ready, retrying..."
    }
    Start-Sleep -Milliseconds 500
    $X++
    if ($X > 50) {exit}
}

# --- Conectar WebSocket ---
$ws = $tab.webSocketDebuggerUrl
$socket = New-Object System.Net.WebSockets.ClientWebSocket
$uri = [Uri]$ws
$socket.ConnectAsync($uri,[Threading.CancellationToken]::None).Wait()

# --- Esperar document.readyState = complete ---

Wait-ForPageReady -Socket $socket -TargetUrl "https://rda.prod.cloud.fedex.com/rda/"Wait-ForPageReady -Socket $socket -TargetUrl "https://rda.prod.cloud.fedex.com/rda/"

# --- Esperar a que localStorage tenga el token ---
$tokenReady = $false
while (-not $tokenReady) {

    $cmd = @'
{"id":2,"method":"Runtime.evaluate","params":{"expression":"localStorage.getItem(\"okta-token-storage\") !== null"}}
'@

    $bytes = [Text.Encoding]::UTF8.GetBytes($cmd)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)

    $socket.SendAsync($segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None).Wait()

    $buffer = New-Object byte[] 10240
    $result = $socket.ReceiveAsync([ArraySegment[byte]]$buffer,
        [Threading.CancellationToken]::None).Result

    $json = [Text.Encoding]::UTF8.GetString($buffer,0,$result.Count)
    $tokenReady = ($json | ConvertFrom-Json).result.result.value

    if (-not $tokenReady) { Start-Sleep -Milliseconds 500 }
}

# --- Esperar token válido (no expirado) ---
$validToken = $false

while (-not $validToken) {

    $cmd = @'
{"id":3,"method":"Runtime.evaluate","params":{"expression":"JSON.stringify(JSON.parse(localStorage.getItem(\"okta-token-storage\")).accessToken)"}}
'@

    $bytes = [Text.Encoding]::UTF8.GetBytes($cmd)
    $segment = New-Object System.ArraySegment[byte] -ArgumentList (, $bytes)

    $socket.SendAsync($segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [Threading.CancellationToken]::None).Wait()

    $buffer = New-Object byte[] 10240
    $result = $socket.ReceiveAsync([ArraySegment[byte]]$buffer,
        [Threading.CancellationToken]::None).Result

    $json = [Text.Encoding]::UTF8.GetString($buffer,0,$result.Count)

    $obj = $json | ConvertFrom-Json

if (-not $obj.result -or -not $obj.result.result -or -not $obj.result.result.value) {
    Start-Sleep -Milliseconds 300
    continue
}

$data = $obj.result.result.value | ConvertFrom-Json

    $token = $data.accessToken
    $expires = $data.expiresAt

    if (-not $token) {
        Write-Host "`rToken aún no disponible..." -NoNewline
        Start-Sleep 1
        continue
    }

    $expiry = [DateTimeOffset]::FromUnixTimeSeconds($expires).ToLocalTime().DateTime

    Write-Host "Token expira:" $expiry

    #if ($expiry -le (Get-Date)) {

        Write-Host "Token expirado → recargando RDA"

        $reload = '{"id":40,"method":"Page.reload"}'
        $bytes = [Text.Encoding]::UTF8.GetBytes($reload)

        $socket.SendAsync(
            [ArraySegment[byte]]::new($bytes),
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            [Threading.CancellationToken]::None
        ).Wait()
        Start-Sleep 2
        Wait-ForPageReady -Socket $socket -TargetUrl "https://rda.prod.cloud.fedex.com/rda/"
        continue
    #}

    $validToken = $true
}

# --- Limpiar BOM ---
$bytes = [System.Text.Encoding]::UTF8.GetBytes($token)

if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = $bytes[3..($bytes.Length-1)]
}

$tokenClean = [System.Text.Encoding]::UTF8.GetString($bytes)

# --- Guardar token ---
[System.IO.File]::WriteAllText("$PSScriptRoot\TOKEN.txt", $tokenClean, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText("$PSScriptRoot\TOKEN_EXPIRES.txt", $expiry, [System.Text.Encoding]::UTF8)

Write-Host "TOKEN GUARDADO: $tokenClean"

# --- Cerrar Edge ---
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -like '*--remote-debugging-port=9222*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Write-Host "EDGE CERRADO"