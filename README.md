# j3kOS - A Fucking Operating System
**by Jortboy3k (@jortboy3k)**

> *"Why the fuck did I make this? Because I could."*

## What the hell is this?

j3kOS is my custom x86 OS that actually boots into 32-bit protected mode without shitting itself. It's got proper flat memory, interrupts that don't crash, and drivers that kinda work. Built this whole thing in assembly because apparently I hate myself.

## How this shit boots

### Stage 1 - The Bootloader (512 bytes of pure chaos)
- BIOS yeeets our code to 0x7C00
- We grab the boot drive and load Stage 2
- 10 sectors of "please don't fuck up" energy
- Jump to Stage 2 like we know what we're doing

### Stage 2 - The Loader (5KB of 16-bit hell)
- Loads the actual 32-bit kernel (20 sectors to 0x10000)
- Enables A20 line (whatever tf that is)
- Sets up the GDT so we can pretend we're professional
- Flips the pmode switch
- Jumps into 32-bit land

### Kernel (The actual OS bit)
- Initializes IDT (256 interrupt gates because fuck it)
- Remaps the PIC (cuz BIOS is shit at IRQ handling)
- Gets the timer running at 100Hz
- Keyboard driver that actually works
- Shell that lets you type shit

## Memory Map (don't fucking touch these)
```
0x00007C00 : Bootloader lives here
0x00001000 : Loader hangs out here  
0x00010000 : Kernel does its thing here
0x00090000 : Stack (hope we don't overflow lol)
0x000B8000 : VGA text buffer (poke this for colors)
0x00100000 : Heap starts here (1MB, malloc your shit)
```

## Features that actually work

### Interrupts n Shit
- **IDT**: 256 interrupt gates cuz why not
- **PIC**: Remapped so it doesn't fight with CPU exceptions
- **Timer**: 100Hz tick for when you need to know wtf is happening
- **Keyboard**: PS/2 with ring buffer, shift/caps lock support, and arrow keys

### Hardware Drivers (kinda)
- **Keyboard**: Type shit, it shows up. Magic.
- **Video**: 80x25 text mode, scrolling works
- **Timer**: Counts ticks since boot
- **RTC**: Real date/time from CMOS
- **PCI**: Scan that bus for hardware
- **RTL8139**: Network card (if you're brave enough)

### System Shit
- **Memory allocator**: malloc/free at 1MB heap
- **System calls**: INT 0x80 interface for syscalls
- **Task switching**: TSS and basic multitasking
- **Command history**: Up/down arrows like a real shell

## Shell Commands (all need : prefix you cuck)

```
:help       - show this shit
:clear      - clear the screen
:time       - timer ticks (boring)
:datetime   - actual date/time from RTC
:timezone   - set timezone offset (+/-n)
:mem        - memory info
:ver        - OS version
:pci        - scan PCI bus for devices
:malloc     - test allocate 256 bytes
:syscall    - test INT 0x80 interface
:tasks      - show task info
:net        - initialize RTL8139 network card
:say <msg>  - echo with dramatic effect
:reboot     - restart (triple fault style)

Files:
:list/:show         - list files
:make/:create <n>   - create file
:read/:open <n>     - read file
:delete/:remove <n> - delete file
```

## Building this clusterfuck

### You need:
- **NASM** - because we're doing this in assembly like cavemen
- **QEMU** - to actually test this without bricking your PC

### Build it:
```bash
.\build.bat
```

### Run it:
```bash
.\test.bat
# or just: qemu-system-i386 -fda j3kOS.img
```

## File Structure
```
j3kOS/
├── boot.asm       - 512 byte bootloader (stage 1)
├── loader.asm     - 5KB loader (stage 2) 
├── kernel32.asm   - the actual OS (32-bit pmode)
├── build.bat      - build this fucking thing
├── test.bat       - run in QEMU
└── j3kOS.img      - bootable floppy image
```

## Technical Shit

### GDT (Global Descriptor Table)
```
0x00 : Null (cuz reasons)
0x08 : Kernel Code (ring 0, 4GB flat)
0x10 : Kernel Data (ring 0, 4GB flat)
0x18 : User Code (ring 3, for syscalls)
0x20 : User Data (ring 3, for syscalls)
0x28 : TSS (task switching bullshit)
```

### Interrupts
```
0x00-0x1F : CPU exceptions (don't trigger these)
0x20      : Timer (ticks every 10ms)
0x21      : Keyboard (type shit here)
0x80      : System calls (INT 0x80)
```

## What Actually Works ✓

- [x] Protected mode with flat memory (no segmentation bullshit)
- [x] IDT with 256 interrupt gates
- [x] PIC remapping (IRQs 32-47)
- [x] PIT timer at 100Hz
- [x] PS/2 keyboard with ring buffer
- [x] Shift, caps lock, and arrow keys
- [x] VGA text mode with scrolling
- [x] Shell with command history (up/down arrows)
- [x] RTC driver for real date/time
- [x] Timezone support
- [x] PCI bus enumeration
- [x] Memory allocator (malloc/free)
- [x] System call interface (INT 0x80)
- [x] Task switching with TSS
- [x] RTL8139 network driver initialization
- [x] File system (in-memory, 16 files)

## TODO (if I feel like it)

- [ ] Actually send/receive network packets
- [ ] TCP/IP stack (lol good luck)
- [ ] File system with actual storage
- [ ] More task switching features
- [ ] User mode programs
- [ ] Not crash randomly

## How to add shit

### New Commands
1. Add the string to the command list
2. Write a handler in `process_command`
3. Update the help text
4. Hope it doesn't break everything

### New Interrupts  
1. Write handler ending with `iret`
2. Install in IDT during `init_idt`
3. Unmask the IRQ in PIC
4. Pray to the assembly gods

## Debugging (when shit breaks)

- QEMU monitor: Ctrl+Alt+2
- Check registers: `info registers`
- Dump memory: `x/32x 0x10000`
- Add print statements everywhere
- Give up and rewrite it

## Credits

Made by **Jortboy3k** because apparently I have nothing better to do.

Hit me up: [@jortboy3k](https://twitter.com/jortboy3k)

## License

Do whatever the fuck you want with it. Just don't blame me when it breaks.
