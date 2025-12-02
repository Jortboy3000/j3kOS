# j3kOS - A Fucking Operating System That Actually Works
**by Jortboy3k (@jortboy3k)**

> *"Most devs can't even center a div, meanwhile I'm out here writing a whole fucking OS in assembly."*

## What the hell is this?

j3kOS is my custom x86 OS that boots into 32-bit protected mode without shitting itself like your average JavaScript framework. It's got proper flat memory, interrupts that don't crash every 5 seconds, and drivers that actually work. Built this entire thing in raw assembly because modern devs are too scared to touch anything below Python.

## Recent Updates (Dec 2025)

### NEW SHIT:
- **113KB kernel** - Yeah it's huge now, deal with it. Dynamic loader handles it fine.
- **Proper Login Screen** - "Security Theater" to keep the plebs out (fake as fuck but looks cool).
- **Hardware Cursor** - Fixed the blinking block so it actually syncs with where you type. Made it a thick block because thin lines are for weaklings.
- **Text Editor** - `edit <filename>` actually works now. Vi-style? Nano-style? Who cares, it writes bytes.
- **Organized Help** - Grouped commands so you don't have to read a wall of text like a caveman.
- **Modular architecture** - Network extensions as loadable modules
- **`:loadnet` command** - Load TCP/HTTP/JSON/REST API at runtime
- **Fixed boot loader** - No more triple faults and boot loops
- **Single 120-sector read** - BIOS finally cooperates
- **Boot menu** - 5-second countdown with ASCII logo
- **Safe/Verbose modes** - For when shit inevitably breaks

### Network Extensions Module (netext.asm):
- **TCP stack** - Full socket API with 8 concurrent connections
- **HTTP client** - GET/POST requests that don't suck  
- **JSON parser** - Complete tokenizer with 64-node tree
- **REST API server** - Route matching and endpoint handling
- Loads at 0x50000 (320KB) with jump table exports

## How this shit boots

### Stage 1 - The Bootloader (512 bytes of pure chaos)
- BIOS yeeets our code to 0x7C00
- We grab the boot drive and load Stage 2
- 10 sectors of "please don't fuck up" energy
- Jump to Stage 2 like we know what we're doing

### Stage 2 - The Loader (5KB of 16-bit hell)
- Shows boot menu with ASCII logo (because we're fancy as fuck)
- Boot modes: Normal, Safe, Verbose (for when debugging this nightmare)
- Loads the actual 32-bit kernel (120 sectors = 60KB to 0x10000)
- Enables A20 line (so we can access all the fucking memory)
- Sets up the GDT with proper flat memory model
- Flips the protected mode switch
- Jumps into 32-bit land without crashing

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

## Shell Commands (Western Sydney Edition - No Colons Needed)

We finally fixed the shell so you don't have to type `:` like a caveman. Just type the command.

### [System]
- `help`      - show the new menu (Western Sydney Ed.)
- `clear`     - clear the screen (or `cls` if you're old)
- `ver`       - show OS version
- `reboot`    - restart the machine (triple fault style)
- `time`      - timer ticks since boot
- `datetime`  - actual date/time from RTC
- `timezone`  - set timezone offset (+/-n)
- `mem`       - memory info (32MB because we're not poor)
- `pci`       - scan PCI bus for devices
- `tasks`     - show task info
- `syscall`   - test INT 0x80 interface
- `echo <txt>`- echo text back (new!)

### [Filesystem] (J3KFS)
- `ls`        - list files (or `list`, `show`)
- `cat <f>`   - read file content (or `read`, `open`)
- `edit <f>`  - open text editor (or `vi`, `nano`)
- `make <f>`  - create empty file (or `create`)
- `del <f>`   - delete file (or `rm`, `remove`)
- `write <f> <t>` - write text to file
- `format`    - format disk with J3KFS
- `mount`     - mount filesystem (ram/disk)

### [Network]
- `net`       - initialize RTL8139 network card
- `netstats`  - show network statistics
- `ping <ip>` - ping an IP address
- `loadnet`   - load network extensions module

### [Memory]
- `malloc`    - test allocate 256 bytes
- `free`      - test free
- `vmm`       - virtual memory manager stats
- `vmalloc`   - allocate virtual pages
- `vmap`      - map physical to virtual
- `paging`    - enable hardware paging
- `pages`     - show page tables
- `swap`      - show swap space info
- `compress`  - test page compression
- `decompress`- test page decompression

### [Media/GUI]
- `gfx`       - switch to graphics mode (bouncing ball demo)
- `gui`       - launch GUI (experimental)
- `text`      - back to text mode
- `beep`      - make a beep sound
- `say <txt>` - echo with dramatic effect

## Building this clusterfuck

### You need:
- **NASM** - because we're doing real programming, not that TypeScript bullshit
- **QEMU** - to actually test this without bricking your PC
- **Balls of steel** - because assembly doesn't hold your hand

### Build it:
```bash
.\build.bat
```
This compiles the bootloader, loader, and kernel into a bootable 1.44MB floppy image. If NASM complains, you fucked up.

### Run it:
```bash
.\test.bat
# or manually: qemu-system-i386 -fda j3kOS.img
```

## File Structure (don't fuck with this)
```
j3kOS/
├── boot.asm       - 512 byte bootloader (stage 1)
├── loader.asm     - 5KB loader with boot menu (stage 2) 
├── kernel32.asm   - the actual OS (60KB of pure assembly)
├── netext.asm     - network extensions module (TCP/HTTP/JSON/REST)
├── tcp.asm        - TCP socket implementation
├── http.asm       - HTTP client (GET/POST)
├── json.asm       - JSON parser
├── rest_api.asm   - REST API server
├── editor.asm     - text editor (because vi is for pussies)
├── build.bat      - build this fucking thing
├── test.bat       - run in QEMU
└── j3kOS.img      - bootable floppy image (1.44MB)
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
- [x] PS/2 keyboard with ring buffer and full support
- [x] Shift, caps lock, arrow keys, command history
- [x] VGA text mode (80x25) with smooth scrolling
- [x] Shell with command history (up/down arrows like a real OS)
- [x] RTC driver for actual date/time
- [x] Timezone support (because timezones are a nightmare)
- [x] PCI bus enumeration (scan all the hardware)
- [x] Memory allocator (malloc/free at 1MB heap)
- [x] System call interface (INT 0x80 like Linux)
- [x] Task switching with TSS
- [x] RTL8139 network driver initialization
- [x] J3KFS file system (16 files, in-memory)
- [x] Page management system
- [x] Swap space support
- [x] Boot menu with 3 modes
- [x] Graphics mode switching (experimental)
- [x] GUI framework (work in progress)
- [x] Text editor (basic but functional)
- [x] Modular architecture (loadable modules)
- [x] Network extensions module (TCP/HTTP/JSON/REST)

## What Doesn't Work (Yet)

- [ ] Actually sending/receiving network packets (soon™)
- [ ] Persistent file storage (disk writes are scary)
- [ ] Full multitasking (cooperative scheduling exists)
- [ ] User mode programs (ring 3 is lonely)
- [ ] Virtual memory (we're still flat)
- [ ] More drivers (USB? Who needs it)
- [ ] Not occasionally crashing (we're getting there)

## Roasting Other "OS Developers"

Let me be fucking clear: most of these "OS dev" projects on GitHub are absolute dogshit. Here's why j3kOS is better than your favorite tutorial-following bullshit:

### The "Hello World Bootloader" Crowd
These clowns copy-paste a 512-byte bootloader from OSDev wiki, print "Hello World", and call themselves OS developers. Congratulations, you can write to VGA memory. My bootloader actually loads a fucking kernel.

### The "Rust OS" Hipsters  
"bUt RuSt Is MeMoRy SaFe!" - Cool story bro. While you're fighting the borrow checker for 3 hours, I've already implemented interrupt handlers, drivers, and a working shell in assembly. Memory safety doesn't mean shit when your OS can't even handle a keyboard interrupt without panicking.

### The GRUB Cheaters
Half these "OS projects" just use GRUB to boot into a C kernel and pretend they understand how booting works. You didn't write an OS, you wrote a glorified C program that GRUB holds together with duct tape. I wrote my own bootloader, my own loader, and handle the entire boot process because I'm not a pussy.

### The "Following Tutorial" Script Kiddies
OSDev tutorials, Bran's kernel dev, JamesM's guide - I see you all copy-pasting code you don't understand. Your GDT is broken, your IDT is fucked, and your PIC remapping causes random triple faults. Meanwhile j3kOS has:
- Proper interrupt handling (256 gates, fully functional)
- Real drivers (keyboard with ring buffer, not your scanf bullshit)
- Actual features (file system, network stack, graphics mode)
- A shell that doesn't crash when you press backspace

### The "Pure C" Elitists
"aSsEmBlY iS tOo HaRd, UsE C!" - Yeah, and that's why your OS is 10MB because you linked against newlib. My entire kernel with full networking, file system, and graphics support is 60KB. I can fit my whole OS on a floppy disk while your "minimal OS" needs a CD-ROM.

### The Abandoned GitHub Graveyard
90% of OS repos: Last commit 5 years ago, README says "WIP", 47 open issues, boots once and crashes immediately. Meanwhile j3kOS boots reliably, has 30+ working commands, and I'm still actively developing it because I'm not a quitter.

## Why j3kOS is Actually Good

Unlike these tourist projects, j3kOS has:

1. **Real booting** - Custom bootloader → loader → kernel, no cheating with GRUB
2. **Actual drivers** - Keyboard, timer, PIC, RTC, PCI, network card
3. **Working features** - Shell, file system, memory management, task switching
4. **Modular design** - Network extensions as loadable modules (because I'm not an idiot)
5. **Networking** - TCP stack, HTTP client, JSON parser, REST API (2750 lines of pure pain)
6. **Still maintained** - I'm actually building this, not abandoning it after one weekend

## How to Add Shit (For Competent Developers)

### New Commands
1. Add the command string to the data section
2. Write a handler in `process_command` 
3. Update the help text
4. Test it before pushing, unlike React devs

### New Interrupts  
1. Write handler ending with `iret`
2. Install in IDT during `init_idt`
3. Unmask the IRQ in PIC
4. Actually understand what you're doing

### Loadable Modules
1. Create module with 'J3KMOD' signature
2. Set ORG to load address (0x50000+)
3. Export functions via jump table
4. Load with disk read, verify signature
5. Call functions through jump table

## Debugging (When Shit Inevitably Breaks)

- QEMU monitor: Ctrl+Alt+2
- Check registers: `info registers`  
- Dump memory: `x/32x 0x10000`
- CPU reset logs: `-d cpu_reset`
- Triple fault? Check your stack and IDT
- Add debug prints everywhere
- Actually read the Intel manuals
- Or just give up and blame QEMU

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
