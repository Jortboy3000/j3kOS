@echo off
echo Starting j3kOS in QEMU...
echo Press Ctrl+Alt+G to release mouse
echo Press Ctrl+Alt+F to toggle fullscreen
echo.

"C:\Program Files\qemu\qemu-system-i386.exe" -drive format=raw,file=j3kOS.img -m 32M
