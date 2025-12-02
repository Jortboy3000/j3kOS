@echo off
setlocal EnableDelayedExpansion

echo ======================================
echo j3kOS Build System v2.1
echo by Jortboy3k (@jortboy3k)
echo ======================================
echo.

REM Pre-build verification
if exist j3kOS.img (
    if exist verify.bat (
        echo [PRE-BUILD] Running verification checks...
        call verify.bat
        if %errorlevel% neq 0 (
            echo.
            echo [WARNING] Previous build had issues
            echo Continuing with rebuild...
            echo.
        ) else (
            echo [PRE-BUILD] Previous build verified successfully
            echo.
        )
    )
)

REM Check for NASM
where nasm >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] NASM not found! Please install NASM assembler.
    exit /b 1
)

REM Clean previous build
echo [CLEAN] Removing old binaries...
if exist *.bin del *.bin 2>nul
if exist j3kOS.img del j3kOS.img 2>nul
if exist build.log del build.log 2>nul
echo   Done.
echo.

REM Build Stage 1: Bootloader (512 bytes, 1 sector)
echo [BUILD] Stage 1: Bootloader (boot.asm)
nasm -f bin boot.asm -o boot.bin || (
    echo [ERROR] Bootloader build failed!
    exit /b 1
)
for %%F in (boot.bin) do set BOOT_SIZE=%%~zF
if !BOOT_SIZE! NEQ 512 (
    echo [ERROR] Bootloader must be exactly 512 bytes, got !BOOT_SIZE! bytes
    exit /b 1
)
echo   OK: !BOOT_SIZE! bytes
echo.

REM Build Stage 2: Loader (5KB, 10 sectors)
echo [BUILD] Stage 2: Loader (loader.asm)
nasm -f bin -w-number-overflow loader.asm -o loader.bin || (
    echo [ERROR] Loader build failed!
    exit /b 1
)
for %%F in (loader.bin) do set LOADER_SIZE=%%~zF
set EXPECTED_LOADER=5120
if !LOADER_SIZE! NEQ !EXPECTED_LOADER! (
    echo [ERROR] Loader must be exactly !EXPECTED_LOADER! bytes ^(10 sectors^), got !LOADER_SIZE! bytes
    exit /b 1
)
echo   OK: !LOADER_SIZE! bytes (10 sectors)
echo.

REM Build Stage 3: Kernel
echo [BUILD] Stage 3: Kernel (kernel32.asm)
nasm -f bin kernel32.asm -o kernel32_temp.bin || (
    echo [ERROR] Kernel build failed!
    exit /b 1
)
for %%F in (kernel32_temp.bin) do set KERNEL_SIZE_RAW=%%~zF
set /a KERNEL_SECTORS_RAW=(!KERNEL_SIZE_RAW! + 511) / 512
echo   OK: !KERNEL_SIZE_RAW! bytes (!KERNEL_SECTORS_RAW! sectors)
echo.

REM Inject kernel size into header (offset 4, 4 bytes little-endian)
echo [HEADER] Injecting kernel size into header...
powershell -NoProfile -Command "$bytes = [IO.File]::ReadAllBytes('kernel32_temp.bin'); $size = $bytes.Length - 16; $bytes[4] = $size -band 0xFF; $bytes[5] = ($size -shr 8) -band 0xFF; $bytes[6] = ($size -shr 16) -band 0xFF; $bytes[7] = ($size -shr 24) -band 0xFF; [IO.File]::WriteAllBytes('kernel32_temp.bin', $bytes)" || (
    echo [ERROR] Header injection failed!
    exit /b 1
)
echo   Injected: !KERNEL_SIZE_RAW! bytes (0x!KERNEL_SIZE_RAW!)
echo.

REM Calculate padding needed (round up to nearest sector, then to 18KB minimum)
set /a KERNEL_SIZE_PADDED=(!KERNEL_SIZE_RAW! + 511) / 512 * 512
if !KERNEL_SIZE_PADDED! LSS 18432 (
    set KERNEL_SIZE_PADDED=18432
)
set /a KERNEL_SECTORS_PADDED=!KERNEL_SIZE_PADDED! / 512
echo [PAD] Padding kernel to !KERNEL_SIZE_PADDED! bytes (!KERNEL_SECTORS_PADDED! sectors)...
powershell -NoProfile -Command "$bytes = [IO.File]::ReadAllBytes('kernel32_temp.bin'); $pad = New-Object byte[] %KERNEL_SIZE_PADDED%; [Array]::Copy($bytes, $pad, [Math]::Min($bytes.Length, %KERNEL_SIZE_PADDED%)); [IO.File]::WriteAllBytes('kernel32.bin', $pad)" || (
    echo [ERROR] Kernel padding failed!
    exit /b 1
)
del kernel32_temp.bin >nul 2>&1
echo   Done.
echo.

REM Create disk image with proper layout
set /a IMAGE_LBA_END=10 + !KERNEL_SECTORS_PADDED!
set /a IMAGE_SIZE_CALC=512 + 5120 + !KERNEL_SIZE_PADDED!
set /a IMAGE_SECTORS_CALC=!IMAGE_SIZE_CALC! / 512
echo [IMAGE] Creating disk image...
echo   Layout:
echo     LBA 0:      Bootloader (1 sector)
echo     LBA 1-10:   Loader (10 sectors)
echo     LBA 11-!IMAGE_LBA_END!:  Kernel (!KERNEL_SECTORS_PADDED! sectors)
echo     Total:      !IMAGE_SECTORS_CALC! sectors (!IMAGE_SIZE_CALC! bytes)
copy /b boot.bin+loader.bin+kernel32.bin j3kOS.img >nul || (
    echo [ERROR] Image creation failed!
    exit /b 1
)

REM Pad image to 1.44MB (2880 sectors) for filesystem support
echo [PAD] Padding image to 1.44MB (2880 sectors)...
powershell -NoProfile -Command "$bytes = [IO.File]::ReadAllBytes('j3kOS.img'); $pad = New-Object byte[] 1474560; [Array]::Copy($bytes, $pad, [Math]::Min($bytes.Length, 1474560)); [IO.File]::WriteAllBytes('j3kOS.img', $pad)" || (
    echo [ERROR] Image padding failed!
    exit /b 1
)

REM Verify image
for %%F in (j3kOS.img) do set IMAGE_SIZE=%%~zF
set /a IMAGE_SECTORS=!IMAGE_SIZE! / 512
echo   OK: !IMAGE_SIZE! bytes (!IMAGE_SECTORS! sectors)
echo.

REM Create build report
echo [REPORT] Generating build.log...
(
    echo j3kOS Build Report
    echo ==================
    echo Date: %date% %time%
    echo.
    echo Components:
    echo   boot.bin:     !BOOT_SIZE! bytes ^(1 sector^)
    echo   loader.bin:   !LOADER_SIZE! bytes ^(10 sectors^)
    echo   kernel32.bin: !KERNEL_SIZE_PADDED! bytes ^(!KERNEL_SECTORS_PADDED! sectors^)
    echo   ^(unpadded: !KERNEL_SIZE_RAW! bytes^)
    echo.
    echo Disk Image:
    echo   j3kOS.img:    !IMAGE_SIZE! bytes ^(!IMAGE_SECTORS! sectors^)
    echo.
    echo LBA Layout:
    echo   LBA 0:      Bootloader
    echo   LBA 1-10:   Loader ^(LBA extensions, 64KB boundary safe^)
    echo   LBA 11-46:  Kernel ^(protected mode, flat memory^)
    echo.
) > build.log

echo ======================================
echo Build complete!
echo ======================================
echo Image: j3kOS.img ^(!IMAGE_SIZE! bytes^)
echo.

REM Post-build verification
echo [POST-BUILD] Running verification checks...
call verify.bat
if %errorlevel% neq 0 (
    echo [ERROR] Build verification failed!
    exit /b 1
)

echo.
echo Run with:
echo   test.bat
echo   qemu-system-i386 -drive format=raw,file=j3kOS.img
echo.
echo See build.log for details.
echo ======================================
