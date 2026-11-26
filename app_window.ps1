Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ip = (Read-Host "Nhap dia chi IP Wi-Fi hien tren man hinh iPhone").Trim()

try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    if (-not $tcpClient.ConnectAsync($ip, 8888).Wait(3000)) { throw "Timeout cong 8888" }
    $writer = New-Object System.IO.StreamWriter($tcpClient.GetStream())
    $writer.AutoFlush = $true
} catch {
    Write-Host "LOI KET NOI: $($_.Exception.Message)" -ForegroundColor Red
    exit
}

$uiW = 390
$uiH = 844

$form = New-Object System.Windows.Forms.Form
$form.Text = "iPhone 12 Pro Max - Chieu & Dieu Khien ($ip)"
$form.ClientSize = New-Object System.Drawing.Size($uiW, $uiH)
$form.BackColor = [System.Drawing.Color]::Black
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$picBox = New-Object System.Windows.Forms.PictureBox
$picBox.Dock = "Fill"
$picBox.SizeMode = "StretchImage"
$form.Controls.Add($picBox)

# Luong doc hinh anh MJPEG tu cong 9100
$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$runspace.SessionStateProxy.SetVariable("picBox", $picBox)
$runspace.SessionStateProxy.SetVariable("mjpegUrl", "http://$ip`:9100")
$runspace.SessionStateProxy.SetVariable("form", $form)

$psStream = [powershell]::Create()
$psStream.Runspace = $runspace
$psStream.AddScript({
    try {
        $req = [System.Net.HttpWebRequest]::Create($mjpegUrl)
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
$psStream.BeginInvoke() | Out-Null

$script:isDown = $false
function Send-Touch($type, $x, $y) {
    $nx = [Math]::Round([Math]::Max(0, [Math]::Min(1, $x / [double]$uiW)), 4)
    $ny = [Math]::Round([Math]::Max(0, [Math]::Min(1, $y / [double]$uiH)), 4)
    try { $writer.WriteLine("$type,$nx,$ny") } catch {}
}

$picBox.Add_MouseDown({ param($s, $e) if ($e.Button -eq "Left") { $script:isDown = $true; Send-Touch 0 $e.X $e.Y } })
$picBox.Add_MouseMove({ param($s, $e) if ($script:isDown) { Send-Touch 1 $e.X $e.Y } })
$picBox.Add_MouseUp({ param($s, $e) if ($script:isDown) { $script:isDown = $false; Send-Touch 2 $e.X $e.Y } })

$form.ShowDialog() | Out-Null
$tcpClient.Close()
$psStream.Dispose()
$runspace.Close()
