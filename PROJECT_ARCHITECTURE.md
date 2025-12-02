# The "Architecture" of j3kOS (If You Can Call It That)
**A Diary of Madness by Jortboy3k's Ghost**
**Date:** December 3, 2025 (The day I lost my sanity)
**Architecture:** x86 32-bit Protected Mode (Because Real Mode is for babies and grandpas)

---

## 1. Memory Map: Where Bytes Go to Die

So, we're using a **Flat Memory Model**. Why? Because segmentation is a crime against humanity committed by Intel in the 70s, and I refuse to participate in it. We enable paging because we're civilized, but let's be honest, it's mostly just to make me feel smart.

### The "Physical" Map (It's all lies anyway)
| Start | End | Size | What's actually there |
| :--- | :--- | :--- | :--- |
| `0x0000` | `0x03FF` | 1 KB | **IVT**. The Real Mode relic. We stomp all over this once we switch to Protected Mode. Good riddance. |
| `0x0400` | `0x04FF` | 256 B | **BDA**. BIOS Data Area. Useful for about 3 milliseconds during boot. |
| `0x7C00` | `0x7DFF` | 512 B | **Bootloader**. The magical 512 bytes that started this nightmare. |
| `0x10000` | `0x1FFFF` | 64 KB | **The Kernel**. Yes, the entire OS core fits in 64KB. Bloatware devs, take notes. |
| `0x90000` | `0x9FFFF` | 64 KB | **Stack**. Grows downwards, like my hopes and dreams. |
| `0xA0000` | `0xBFFFF` | 128 KB | **VGA Memory**. Where pixels go to party. Don't touch this unless you want seizure-inducing glitches. |
| `0x100000` | `0x1FFFFF` | 1 MB | **The Heap**. A whole Megabyte. Don't spend it all in one place, you greedy pig. |

### GDT (Global Descriptor Table)
We set up a "Flat" model. Code and Data segments both span the full 4GB.
*   **0x08**: Kernel Code. Execute whatever you want.
*   **0x10**: Kernel Data. Write whatever you want.
*   **Security**: Non-existent. If you want to overwrite the kernel, go ahead. It's your funeral.

---

## 2. IDT: The "Interrupts Are Annoying" Table

The IDT has 256 entries. Most of them are just there to catch CPU exceptions when I divide by zero (which happens more often than I'd like to admit).

### The PIC Remapping Disaster
The Programmable Interrupt Controller (PIC). A piece of hardware designed by sadists. By default, it maps IRQs to `0x08`-`0x0F`. You know what else lives there? **CPU Exceptions**. So if you get a Double Fault, the CPU thinks it's IRQ0 (Timer). Genius design, IBM. Truly genius.

So I remapped them:
*   **Master PIC**: `0x20` - `0x27` (Because `0x20` is a nice round number).
*   **Slave PIC**: `0x28` - `0x2F` (The ugly stepchild of interrupts).

### The Vector Map (A.K.A. The List of Things That Interrupt Me)
*   `0x00`-`0x1F`: **CPU Screaming**. (Page Faults, GPFs, the usual).
*   `0x20` (IRQ0): **PIT Timer**. The heartbeat of the OS. It wakes me up every millisecond to tell me nothing has changed.
*   `0x21` (IRQ1): **Keyboard**. Every time you smash a key, I have to deal with it.
*   `0x2B` (IRQ11): **RTL8139**. The network card. It screams whenever a packet arrives. Usually spam.
*   `0x2C` (IRQ12): **PS/2 Mouse**. The bane of my existence. See Section 6.
*   `0x80`: **Syscalls**. The only way you peasants (User Mode) are allowed to talk to me (Kernel).

---

## 3. Syscalls: Begging the Kernel for Mercy

You want to do something useful? You have to ask nicely via `int 0x80`.

| EAX | Name | Arguments | My Internal Monologue |
| :--- | :--- | :--- | :--- |
| `0` | `EXIT` | None | "Finally, you're leaving." |
| `1` | `PRINT` | `EBX`=String | "Fine, I'll put pixels on the screen. Are you happy now?" |
| `2` | `READ` | `EBX`=Buf | "You want input? Type faster." |
| `3` | `MALLOC` | `ECX`=Size | "Here's some RAM. Don't leak it." |
| `4` | `FREE` | `EBX`=Ptr | "Thank you for recycling." |

---

## 4. J3KFS: Because FAT12 Was Too Mainstream

I wrote my own file system. Why? Because I hate myself. It's an inode-based system on a floppy disk. Yes, a floppy disk. In 2025.

### The Disk Layout (1.44 MB of Pure Power)
*   **LBA 0**: Bootloader.
*   **LBA 11**: Kernel.
*   **LBA 501**: **Swap Space**. When you run out of that precious 1MB heap, I start dumping your memory here. It's slow, it's ugly, but it works.
*   **LBA 1000**: **Superblock**. The god object of the filesystem.
*   **LBA 1001**: **Inode Table**. We support 128 files. If you need more, buy a hard drive.

### Inodes (64 bytes of metadata)
We track file size, block counts, and 12 direct block pointers. Indirect blocks? Pfft. If your file is bigger than 6KB (12 * 512), you don't deserve to save it.

---

## 5. Memory Management: "Hot or Not" for Pages

I implemented a page tracking system that treats memory pages like contestants on a reality TV show.

*   **HOT**: You accessed this page 10 times recently? You're a star. You stay in RAM.
*   **COLD**: Haven't touched this page in 2 ticks? You're dead to me.
*   **COMPRESSED**: If you're COLD, I squash you with RLE compression. It's like Spanx for data.
*   **SWAPPED**: If I'm really out of space (High Pressure), I banish you to the disk (LBA 501). Have fun in the void.

---

## 6. Drivers: The Hardware Hall of Shame

### PS/2 Mouse (The "Production Ready" Nightmare)
Getting a PS/2 mouse to work is like performing a rain dance while solving a Rubik's cube.
1.  **Disable Everything**: Shut down the keyboard and mouse ports.
2.  **Flush**: Read the buffer until it's empty. If it's not empty, read it again.
3.  **The CCB**: Read the Controller Command Byte. Flip bits like a madman (Enable IRQ12, Disable Clock). Write it back.
4.  **The Reset**: Send `0xFF`. Pray for `0xFA` (ACK) and `0xAA` (Self-Test Pass). If you get `0xFC` (Error), cry.
5.  **Enable**: Send `0xF4`. Now the mouse will spam interrupts at you.

**Packet Format**: It sends 3 bytes.
*   Byte 0: A mess of overflow bits and button states. **Bit 3 must be 1**. If it's not, the mouse is lying to you.
*   Byte 1: X movement.
*   Byte 2: Y movement.

### RTL8139 Network
It uses PCI. It uses Ring Buffers. It works in QEMU. Does it work on real hardware? Who knows. I'm not brave enough to try.

---

## 7. The Build System (`build.bat`)

A batch script held together by duct tape and prayers.
1.  **NASM**: Compiles the assembly. If this fails, you broke it.
2.  **Padding**: We pad binaries to sector boundaries because the disk controller is OCD.
3.  **Copy /b**: We mash everything into `j3kOS.img`.
4.  **QEMU**: We launch the emulator and hope it doesn't crash immediately.

---

*End of Log. If you're reading this, I'm probably debugging a Triple Fault.*
