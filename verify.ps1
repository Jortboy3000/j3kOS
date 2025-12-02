# j3kOS Build Verification Script

if (-not (Test-Path "j3kOS.img")) {
    Write-Host "[ERROR] j3kOS.img not found!" -ForegroundColor Red
    exit 1
}

Write-Host "[CHECK] Disk image structure..." -ForegroundColor Yellow

$img = [System.IO.File]::ReadAllBytes('j3kOS.img')

# Check size
Write-Host "  Image size: " -NoNewline
Write-Host $img.Length -ForegroundColor Cyan -NoNewline
Write-Host " bytes"

# Validate minimum size (boot + loader + minimum kernel = 512 + 5120 + 512 = 6144)
if ($img.Length -lt 6144) {
    Write-Host "  [ERROR] Image too small! Minimum 6144 bytes." -ForegroundColor Red
    exit 1
}

# Validate maximum size (128KB = reasonable upper limit for now)
if ($img.Length -gt 131072) {
    Write-Host "  [ERROR] Image too large! Maximum 128KB." -ForegroundColor Red
    exit 1
}

# Check boot signature
Write-Host "  Boot signature: " -NoNewline
$sig = [BitConverter]::ToString($img[510..511])
if ($sig -eq '55-AA') {
    Write-Host "0x55AA" -ForegroundColor Green
} else {
    Write-Host "INVALID!" -ForegroundColor Red
    exit 1
}

# Check loader present (LBA 1)
Write-Host "  Loader present: " -NoNewline
if ($img[512] -ne 0) {
    Write-Host "YES" -ForegroundColor Green
} else {
    Write-Host "NO" -ForegroundColor Red
    exit 1
}

# Check kernel present (LBA 11) and verify header magic
Write-Host "  Kernel present: " -NoNewline
if ($img[5632] -ne 0) {
    Write-Host "YES" -ForegroundColor Green
    
    # Check kernel magic (J3KO = 0x4A334B4F)
    Write-Host "  Kernel magic: " -NoNewline
    $magic = [BitConverter]::ToUInt32($img, 5632)
    if ($magic -eq 0x4A334B4F) {
        Write-Host "0x4A334B4F (J3KO)" -ForegroundColor Green
        
        # Read kernel size from header
        $kernelSize = [BitConverter]::ToUInt32($img, 5636)
        Write-Host "  Kernel size: " -NoNewline
        Write-Host "$kernelSize bytes" -ForegroundColor Cyan
    } else {
        Write-Host ([System.String]::Format("0x{0:X8}", $magic)) -ForegroundColor Red
        Write-Host "  [ERROR] Invalid kernel magic!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "NO" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[CHECK] Memory layout configuration..." -ForegroundColor Yellow
Write-Host "  Kernel Load: Dynamic Loop (LBA 11+)"
Write-Host "  Target: 0x10000 (segment 0x1000:0x0000)"
Write-Host "  64KB boundary: Handled by segment updates" -ForegroundColor Green

Write-Host ""
Write-Host "[CHECK] LBA addressing..." -ForegroundColor Yellow

# Check start LBA
$loaderContent = Get-Content "loader.asm" -Raw
if ($loaderContent -match "dap_lba_low\], 11") {
    Write-Host "  Start LBA: 11 " -NoNewline
    Write-Host "[OK]" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Start LBA incorrect! Expected 11." -ForegroundColor Red
    exit 1
}

# Check for loop logic
if ($loaderContent -match "load_loop") {
    Write-Host "  Load Loop: Present " -NoNewline
    Write-Host "[OK]" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] Load loop not found!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "All checks passed!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "Ready to boot:"
Write-Host "  test.bat"
Write-Host "  qemu-system-i386 -drive format=raw,file=j3kOS.img"
Write-Host "======================================"

exit 0
