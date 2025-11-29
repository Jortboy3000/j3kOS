# j3kOS Protected Mode Implementation Guide
**Technical Reference for Developers**

## Boot Process Flow

### Stage 1: Bootloader (boot.asm)
```
1. BIOS loads sector 0 to 0x7C00
2. CLI, set up segments (DS=ES=SS=0)
3. Set stack pointer to 0x7C00
4. Save boot drive number
5. Use INT 13h to load 10 sectors to 0x1000
6. Jump to 0x1000:0x0000
```

### Stage 2: Loader (loader.asm)
```
1. Enable A20 line (BIOS method, then keyboard controller)
2. Load GDT with flat memory model
3. Load 32-bit kernel (20 sectors) to 0x10000
4. Set CR0 bit 0 to enter protected mode
5. Far jump to flush pipeline: jmp 0x08:protected_mode_entry
6. Set all segments to 0x10 (data selector)
7. Set ESP to 0x90000 (576KB)
8. Jump to 0x10000 (kernel entry)
```

### Stage 3: Kernel (kernel32_flat.asm)
```
1. Clear screen
2. Initialize IDT (256 entries)
3. Remap PIC (master: 0x20-0x27, slave: 0x28-0x2F)
4. Initialize PIT (Channel 0, 100Hz)
5. Initialize keyboard driver
6. STI (enable interrupts)
7. Enter shell loop
```

## Detailed Component Implementation

### A20 Line Enabling
The A20 line must be enabled to access memory above 1MB:

**Method 1: BIOS (Fast)**
```nasm
mov ax, 0x2401
int 0x15
```

**Method 2: Keyboard Controller (Reliable)**
```nasm
; Wait for input buffer empty
.wait1:
    in al, 0x64
    test al, 2
    jnz .wait1

; Send command to read output port
mov al, 0xD0
out 0x64, al

; Wait for output buffer full
.wait2:
    in al, 0x64
    test al, 1
    jz .wait2

; Read output port value
in al, 0x60
push ax

; Write to output port
mov al, 0xD1
out 0x64, al

; Enable A20 (bit 1)
pop ax
or al, 2
out 0x60, al
```

### GDT Structure
Each GDT entry is 8 bytes:

```
Offset  Size  Description
------  ----  -----------
0       2     Limit (bits 0-15)
2       2     Base (bits 0-15)
4       1     Base (bits 16-23)
5       1     Access byte (present, DPL, type)
6       1     Flags + Limit (bits 16-19)
7       1     Base (bits 24-31)
```

**Code Segment (0x08):**
```
Base:  0x00000000
Limit: 0xFFFFF (4GB with 4K granularity)
Access: 0x9A (Present, Ring 0, Code, Readable, Executable)
Flags:  0xCF (4K granularity, 32-bit)
```

**Data Segment (0x10):**
```
Base:  0x00000000
Limit: 0xFFFFF (4GB with 4K granularity)
Access: 0x92 (Present, Ring 0, Data, Writable)
Flags:  0xCF (4K granularity, 32-bit)
```

### IDT Structure
Each IDT entry is 8 bytes:

```
Offset  Size  Description
------  ----  -----------
0       2     Handler address (bits 0-15)
2       2     Code segment selector (0x08)
4       1     Reserved (0)
5       1     Type (0x8E = 32-bit interrupt gate)
6       2     Handler address (bits 16-31)
```

**Type Byte (0x8E):**
```
Bit 7:    Present (1)
Bits 6-5: DPL (00 = Ring 0)
Bit 4:    Storage segment (0)
Bits 3-0: Type (1110 = 32-bit interrupt gate)
```

### PIC Remapping
The PIC must be remapped to avoid conflicts with CPU exceptions:

```nasm
; ICW1: Initialize
mov al, 0x11
out 0x20, al    ; Master
out 0xA0, al    ; Slave

; ICW2: Vector offsets
mov al, 0x20
out 0x21, al    ; Master IRQ0-7 → INT 0x20-0x27
mov al, 0x28
out 0xA1, al    ; Slave IRQ8-15 → INT 0x28-0x2F

; ICW3: Cascade
mov al, 0x04
out 0x21, al    ; Master has slave on IRQ2
mov al, 0x02
out 0xA1, al    ; Slave cascade identity

; ICW4: 8086 mode
mov al, 0x01
out 0x21, al
out 0xA1, al

; Unmask IRQs (0 = enabled, 1 = masked)
mov al, 0xFC    ; Enable IRQ0 (timer) and IRQ1 (keyboard)
out 0x21, al
mov al, 0xFF    ; Mask all slave IRQs
out 0xA1, al
```

### PIT Configuration
Set timer frequency = 1193182 Hz / divisor

**For 100Hz (10ms ticks):**
```nasm
mov al, 0x36    ; Channel 0, lohi, rate generator
out 0x43, al

mov ax, 11932   ; 1193182 / 100
out 0x40, al    ; Low byte
mov al, ah
out 0x40, al    ; High byte
```

### Keyboard Driver
**PS/2 Scancode Set 1 (Make Codes):**
```
Scancode  Key     Scancode  Key
--------  ---     --------  ---
0x01      ESC     0x1C      Enter
0x02-0x0B 1-0     0x1D      LCtrl
0x0E      Backsp  0x2A      LShift
0x0F      Tab     0x36      RShift
0x10-0x1B QWERTY  0x38      LAlt
         row      0x39      Space
0x1E-0x26 ASDFGH  0x3A      Caps
         row
0x2C-0x32 ZXCVBN  +0x80     = Release
         row
```

**Ring Buffer Implementation:**
```
write_pos: Points to next write location
read_pos:  Points to next read location

Empty:  write_pos == read_pos
Full:   (write_pos + 1) % size == read_pos

Write: buffer[write_pos] = data; write_pos = (write_pos+1) % size
Read:  data = buffer[read_pos]; read_pos = (read_pos+1) % size
```

### VGA Text Mode
**Memory Layout (0xB8000):**
```
Each character = 2 bytes
  Byte 0: ASCII character
  Byte 1: Attribute (0x0F = white on black)

Position calculation:
  offset = (row * 80 + col) * 2 + 0xB8000
```

**Scrolling:**
```
1. Copy lines 1-24 to lines 0-23
   Source: 0xB8000 + 160 (line 1)
   Dest:   0xB8000
   Count:  80*24 words

2. Clear line 24
   Fill 80 words with 0x0F20 (space)
```

## Interrupt Handler Template

```nasm
irq_handler:
    ; Save all registers
    pusha
    
    ; Handler code here
    ; ...
    
    ; Send EOI to PIC
    mov al, 0x20
    out 0x20, al    ; Master PIC
    ; For IRQ8-15, also send to slave:
    ; out 0xA0, al
    
    ; Restore registers
    popa
    
    ; Return from interrupt
    iret
```

## Common I/O Ports

```
Port    Device
----    ------
0x20    Master PIC Command
0x21    Master PIC Data/Mask
0x40    PIT Channel 0 Data
0x43    PIT Command
0x60    Keyboard Data
0x64    Keyboard Status/Command
0xA0    Slave PIC Command
0xA1    Slave PIC Data/Mask
```

## Debugging Tips

### QEMU Monitor Commands
```
Ctrl+Alt+2      - Switch to monitor
Ctrl+Alt+1      - Back to VM

info registers  - Show CPU registers
x/32x 0x10000  - Examine memory (32 hex words at 0x10000)
x/i 0x10000    - Disassemble instruction
info pic       - Show PIC state
info mem       - Show memory mappings
```

### Common Issues

**Triple Fault (Reboot Loop):**
- IDT not properly initialized
- Stack overflow/underflow
- Invalid segment selector
- Unhandled exception

**No Keyboard Input:**
- PIC not unmasking IRQ1
- IDT entry for INT 0x21 incorrect
- Not sending EOI in handler

**Screen Artifacts:**
- Cursor position not tracked correctly
- Missing scrolling implementation
- Writing beyond video buffer

**Timer Not Working:**
- PIT not initialized
- PIC masking IRQ0
- IDT entry for INT 0x20 incorrect

## Performance Considerations

- **Interrupt Latency**: Keep handlers short, defer work if possible
- **Video Updates**: Batch writes to reduce flicker
- **Keyboard Buffer**: 256 bytes sufficient for normal typing
- **Stack Size**: 16KB minimum for kernel, 4KB per task

## Next Steps for Networking

### PCI Device Enumeration
1. Scan bus 0, devices 0-31
2. Read vendor/device ID from config space
3. Match RTL8139 (vendor 0x10EC, device 0x8139)
4. Read BAR0 for I/O port base

### RTL8139 Initialization
1. Power on device (CONFIG1 register)
2. Software reset
3. Set up TX descriptors (4 buffers)
4. Set up RX buffer (8KB+16 bytes)
5. Enable transmitter and receiver
6. Set interrupt mask

### Packet Transmission
1. Copy packet to TX buffer
2. Write length to TSD register
3. Wait for TX_OK interrupt
4. Handle next packet

---
**by Jortboy3k (@jortboy3k)**
