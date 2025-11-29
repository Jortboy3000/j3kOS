@echo off
echo ======================================
echo Building j3kOS (Flat Binary Method)
echo by Jortboy3k (@jortboy3k)
echo ======================================
echo.

REM Check for NASM
where nasm >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: NASM not found!
    exit /b 1
)

REM Clean
echo Cleaning...
if exist *.bin del *.bin
if exist j3kOS.img del j3kOS.img

REM Build
echo.
echo Building bootloader...
nasm -f bin boot.asm -o boot.bin || exit /b 1

echo Building loader...
nasm -f bin loader.asm -o loader.bin || exit /b 1

echo Building kernel...
nasm -f bin kernel32.asm -o kernel32.bin || exit /b 1

REM Pad kernel to 10KB
echo.
echo Padding kernel...
powershell -Command "$bytes = [IO.File]::ReadAllBytes('kernel32.bin'); $pad = New-Object byte[] 10240; [Array]::Copy($bytes, $pad, [Math]::Min($bytes.Length, 10240)); [IO.File]::WriteAllBytes('kernel32.bin', $pad)"

REM Create image
echo Creating disk image...
copy /b boot.bin+loader.bin+kernel32.bin j3kOS.img >nul

echo.
echo ======================================
echo Build complete!
echo Run: qemu-system-i386 -fda j3kOS.img
echo ======================================
