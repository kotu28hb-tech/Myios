Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ip = (Read-Host "Nhap dia chi IP Wi-Fi cua iPhone (vi du 192.168.1.87)").Trim()
$baseUrl = "http://$ip`:8100"
$mjpegUrl = "http://$ip`:9100"

# 1. Khoi tao phien dieu khien WDA (Session)
Write-Host "Dang ket noi toi WebDriverAgent tren iPhone..." -ForegroundColor Cyan
try {
    $sessionBody = '{"capabilities":{"alwaysMatch":{"platformName":"iOS"}}}'
    $resp = Invoke-RestMethod -Uri "$baseUrl/session" -Method Post -Body $sessionBody -ContentType "application/json" -TimeoutSec 5
    $sessionId = $resp.sessionId
    if (-not $sessionId) { $sessionId = $resp.value.sessionId }
    
    # Lay kich thuoc diem anh (Points) cua man hinh iPhone 12 Pro Max (428 x 926)
    $winSize = Invoke-RestMethod -Uri "$baseUrl/session/$sessionId/window/size" -Method Get
    $iosW = [double]$winSize.value.width
    $iosH = [double]$winSize.value.height
    Write-Host "KET NOI THANH CONG! Do phan giai iOS: ${iosW}x${iosH}" -ForegroundColor Green
} catch {
    Write-Host "KHONG THE KET NOI TOI $baseUrl : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Hay dam bao ban da mo app WebDriverAgentRunner-Runner tren iPhone!" -ForegroundColor Yellow
    exit
}

# 2. Tao cua so hien thi man hinh iPhone tren Windows
$uiW = 390
$uiH = [int]($uiW * ($iosH / $iosW))

$form = New-Object System.Windows.Forms.Form
$form.Text = "iPhone 12 Pro Max Mirror & Control ($ip)"
$form.ClientSize = New-Object System.Drawing.Size($uiW, ($uiH + 40))
$form.BackColor = [System.Drawing.Color]::Black
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$picBox = New-Object System.Windows.Forms.PictureBox
$picBox.Location = New-Object System.Drawing.Point(0, 0)
$picBox.Size = New-Object System.Drawing.Size($uiW, $uiH)
$picBox.SizeMode = "StretchImage"
$form.Controls.Add($picBox)

# Thanh nut bam nhanh phia duoi (Home, Lock, Volume)
$btnHome = New-Object System.Windows.Forms.Button
$btnHome.Text = "Nut Home"
$btnHome.Location = New-Object System.Drawing.Point(10, ($uiH + 5))
$btnHome.Size = New-Object System.Drawing.Size(110, 30)
$btnHome.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 50)
$btnHome.ForeColor = [System.Drawing.Color]::White
$btnHome.FlatStyle = "Flat"
$btnHome.Add_Click({
    Invoke-RestMethod -Uri "$baseUrl/wda/homescreen" -Method Post -Body "{}" -ContentType "application/json" | Out-Null
})
$form.Controls.Add($btnHome)

# 3. Luong nen (Background Runspace) doc luong hinh anh MJPEG tu cong 9100
$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$runspace.SessionStateProxy.SetVariable("picBox", $picBox)
$runspace.SessionStateProxy.SetVariable("mjpegUrl", $mjpegUrl)
$runspace.SessionStateProxy.SetVariable("form", $form)

$psStream = [powershell]::Create()
$psStream.Runspace = $runspace
$psStream.AddScript({
    try {
        $req = [System.Net.HttpWebRequest]::Create($mjpegUrl)
        $req.Timeout = 5000
        $res = $req.GetResponse()
        $stream = $res.GetResponseStream()
        
        $buffer = New-Object byte[] 65536
        $imgBytes = New-Object System.Collections.Generic.List[byte]
        $inJpeg = $false
        $prevByte = 0

        while (-not $form.IsDisposed) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            for ($i = 0; $i -lt $read; $i++) {
                $b = $buffer[$i]
                if ($prevByte -eq 0xFF -and $b -eq 0xD8) {
                    $imgBytes.Clear()
                    $imgBytes.Add(0xFF)
                    $inJpeg = $true
                }
                if ($inJpeg) {
                    $imgBytes.Add($b)
                    if ($prevByte -eq 0xFF -and $b -eq 0xD9) {
                        $inJpeg = $false
                        try {
                            $ms = New-Object System.IO.MemoryStream(,$imgBytes.ToArray())
                            $bmp = [System.Drawing.Image]::FromStream($ms)
                            if (-not $form.IsDisposed) {
                                $picBox.Invoke([Action]{
                                    $old = $picBox.Image
                                    $picBox.Image = $bmp
                                    if ($null -ne $old) { $old.Dispose() }
                                })
                            }
                        } catch {}
                    }
                }
                $prevByte = $b
            }
        }
    } catch {}
}) | Out-Null
$handle = $psStream.BeginInvoke()

# 4. Xu ly su kien Click va Vuot chuot tren man hinh iPhone
$script:downX = 0
$script:downY = 0
$script:downTime = [DateTime]::Now

$picBox.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq "Left") {
        $script:downX = [int](($e.X / $uiW) * $iosW)
        $script:downY = [int](($e.Y / $uiH) * $iosH)
        $script:downTime = [DateTime]::Now
    }
})

$picBox.Add_MouseUp({
    param($s, $e)
    if ($e.Button -eq "Left") {
        $upX = [int](($e.X / $uiW) * $iosW)
        $upY = [int](($e.Y / $uiH) * $iosH)
        $dist = [Math]::Sqrt([Math]::Pow($upX - $script:downX, 2) + [Math]::Pow($upY - $script:downY, 2))
        
        if ($dist -lt 10) {
            # Thao tac Cham (Tap)
            $body = "{`"actions`":[{`"type`":`"pointer`",`"id`":`"finger1`",`"parameters`":{`"pointerType`":`"touch`"},`"actions`":[{`"type`":`"pointerMove`",`"duration`":0,`"x`":$upX,`"y`":$upY},{`"type`":`"pointerDown`",`"button`":0},{`"type`":`"pause`",`"duration`":50},{`"type`":`"pointerUp`",`"button`":0}]}]}"
        } else {
            # Thao tac Vuot (Swipe)
            $dur = [Math]::Max(150, [Math]::Min(800, [int]([DateTime]::Now - $script:downTime).TotalMilliseconds))
            $body = "{`"actions`":[{`"type`":`"pointer`",`"id`":`"finger1`",`"parameters`":{`"pointerType`":`"touch`"},`"actions`":[{`"type`":`"pointerMove`",`"duration`":0,`"x`":$($script:downX),`"y`":$($script:downY)},{`"type`":`"pointerDown`",`"button`":0},{`"type`":`"pointerMove`",`"duration`":$dur,`"x`":$upX,`"y`":$upY},{`"type`":`"pointerUp`",`"button`":0}]}]}"
        }
        try {
            Invoke-RestMethod -Uri "$baseUrl/session/$sessionId/actions" -Method Post -Body $body -ContentType "application/json" | Out-Null
        } catch {}
    }
})

$form.ShowDialog() | Out-Null
$psStream.Dispose()
$runspace.Close()
