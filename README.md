# j3kOS - Protected Mode Operating System
**by Jortboy3k (@jortboy3k)**

## Overview
j3kOS is a custom x86 operating system that boots into 32-bit protected mode with a proper flat memory model, interrupt handling, and device drivers.

## Architecture

### Boot Sequence
1. **Stage 1 - Bootloader (512 bytes at 0x7C00)**
   - BIOS loads first sector to 0x7C00
   - Sets up segments, saves boot drive
   - Loads Stage 2 (10 sectors) to 0x1000
   - Jumps to Stage 2

2. **Stage 2 - Loader (5KB at 0x1000)**
   - Loads 32-bit kernel (20 sectors) to 0x10000
   - Enables A20 line for full memory access
   - Sets up GDT (Global Descriptor Table)
   - Switches to protected mode
   - Jumps to 32-bit kernel

3. **Kernel (32-bit at 0x10000)**
   - Initializes IDT (Interrupt Descriptor Table)
   - Remaps PIC (Programmable Interrupt Controller)
   - Sets up PIT timer at 100Hz
   - Initializes keyboard driver
   - Launches interactive shell

### Memory Layout
```
0x00000000 - 0x000003FF : Real Mode IVT (unused in pmode)
0x00000400 - 0x000004FF : BIOS Data Area
0x00000500 - 0x00007BFF : Free conventional memory
0x00007C00 - 0x00007DFF : Bootloader (512 bytes)
0x00007E00 - 0x00000FFF : Stack space
0x00001000 - 0x00002400 : Loader (5KB)
0x00010000 - 0x00012800 : 32-bit Kernel (10KB)
0x00090000 - 0x0009FFFF : Kernel stack
0x000A0000 - 0x000BFFFF : VGA memory
0x000B8000 - 0x000B8FA0 : Text mode video buffer
```

### Features

#### Interrupt Handling
- **IDT**: 256 interrupt gates
- **PIC**: Remapped to IRQ 32-47 (avoids conflict with CPU exceptions)
- **IRQ0 (Timer)**: 100Hz tick rate for timing
- **IRQ1 (Keyboard)**: PS/2 keyboard with scancode translation

#### Device Drivers
- **Keyboard**: Ring buffer with 256-byte capacity, US QWERTY layout
- **Video**: Direct VGA text mode access at 0xB8000, 80x25 characters
- **Timer**: Millisecond precision timing from PIT

#### Shell Commands
- `help` - Display available commands
- `clear` - Clear the screen
- `time` - Show timer ticks since boot

## Building

### Prerequisites
- **NASM** (Netwide Assembler) - [Download](https://www.nasm.us/)
- **QEMU** (optional, for testing) - [Download](https://www.qemu.org/)

### Build Instructions
```bash
# Build the OS image
.\build_simple.bat

# Output: j3kOS.img (31.5KB floppy image)
```

### Running
```bash
# Run in QEMU
.\test32.bat

# Or manually:
qemu-system-i386 -fda j3kOS.img -m 32M
```

## File Structure
```
j3kOS/
├── boot.asm           - Stage 1 bootloader (512 bytes)
├── loader.asm         - Stage 2 loader (5KB, 16-bit)
├── kernel32_flat.asm  - 32-bit protected mode kernel
├── build_simple.bat   - Build script
├── test32.bat         - QEMU test launcher
└── j3kOS.img          - Bootable floppy image
```

## Technical Details

### Global Descriptor Table (GDT)
```
Null Descriptor  : 0x00
Code Segment     : 0x08 (Base: 0, Limit: 4GB, R/X)
Data Segment     : 0x10 (Base: 0, Limit: 4GB, R/W)
```

### Interrupt Vector Table
```
0x00-0x1F : CPU Exceptions
0x20      : IRQ0 - PIT Timer
0x21      : IRQ1 - Keyboard
0x22-0x2F : IRQ2-15 (reserved)
0x30-0xFF : Available for software interrupts
```

### Keyboard Scancodes
The keyboard driver translates PS/2 Set 1 scancodes to ASCII using a lookup table for US QWERTY layout.

## Roadmap

### Completed ✓
- [x] Protected mode transition with flat memory model
- [x] IDT and interrupt handling
- [x] PIC initialization and IRQ remapping
- [x] PIT timer at 100Hz
- [x] PS/2 keyboard driver with ring buffer
- [x] VGA text mode output with scrolling
- [x] Interactive shell with command parsing

### In Progress
- [ ] Test kernel functionality
- [ ] Add more shell commands

### Planned
- [ ] PCI bus enumeration
- [ ] RTL8139 network driver
- [ ] TCP/IP stack (ARP, ICMP, UDP, TCP)
- [ ] File system support
- [ ] Multitasking
- [ ] User mode programs

## Development Notes

### Adding New Commands
1. Add command string to data section
2. Implement handler in `process_command`
3. Add to help text

### Adding New Interrupts
1. Create handler function ending with `iret`
2. Install in IDT during `init_idt`
3. Unmask IRQ in PIC if needed

### Debugging
- Use QEMU monitor (Ctrl+Alt+2) for debugging
- Check register states with `info registers`
- View memory with `x/32x 0x10000`

## Credits
Created by **Jortboy3k**  
Twitter/X: [@jortboy3k](https://twitter.com/jortboy3k)

## License
Educational project - feel free to learn from and modify!
