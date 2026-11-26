Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ip = Read-Host "Nhap dia chi IP hien tren man hinh iPhone (vi du 192.168.1.15)"
$client = New-Object System.Net.Sockets.TcpClient($ip, 8888)
$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream)
$writer.AutoFlush = $true

# Tao cua so mo phong ty le man hinh iPhone 12 Pro Max (360 x 780)
$form = New-Object System.Windows.Forms.Form
$form.Text = "Dieu khien iPhone 12 Pro Max ($ip)"
$form.ClientSize = New-Object System.Drawing.Size(360, 780)
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "Click hoac keo chuot trong khung nay`nde cham / vuot tren man hinh iPhone"
$lbl.ForeColor = [System.Drawing.Color]::LightGray
$lbl.Dock = "Fill"
$lbl.TextAlign = "MiddleCenter"
$form.Controls.Add($lbl)

$script:isDown = $false
function Send-TouchEvent($type, $x, $y) {
    $nx = [Math]::Round([Math]::Max(0, [Math]::Min(1, $x / 360.0)), 4)
    $ny = [Math]::Round([Math]::Max(0, [Math]::Min(1, $y / 780.0)), 4)
    $writer.WriteLine("$type,$nx,$ny")
}

$lbl.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq "Left") {
        $script:isDown = $true
        Send-TouchEvent 0 $e.X $e.Y
    }
})

$lbl.Add_MouseMove({
    param($s, $e)
    if ($script:isDown) {
        Send-TouchEvent 1 $e.X $e.Y
    }
})

$lbl.Add_MouseUp({
    param($s, $e)
    if ($script:isDown) {
        $script:isDown = $false
        Send-TouchEvent 2 $e.X $e.Y
    }
})

$form.ShowDialog() | Out-Null
$client.Close()
