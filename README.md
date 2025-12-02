# j3kOS

**A 32-bit Operating System written in x86 Assembly. Because C is for cowards.**

Let's be real: writing an OS in C is too easy. You include a header, call a function, and pretend you understand what the CPU is doing. j3kOS is built different. It's 100% raw x86 assembly. No standard library, no GRUB, no hand-holding. Just me, the hardware, and a lot of triple faults.

If you want to see what a computer actually does before the bloatware takes over, look inside. If you're looking for a stable daily driver, go install Linux.

## What is this monstrosity?

It's a monolithic kernel that boots from a floppy disk (because retro), switches to 32-bit protected mode, and lets you poke around memory. It's not "production ready"it's "learning ready".

### The Specs (Yes, it actually works)

*   **Bootloader**: Custom 2-stage loader. I didn't use GRUB because I'm not lazy. It loads the kernel, enables the A20 line, and sets up the GDT.
*   **Kernel**: Runs in 32-bit Protected Mode. Flat memory model. No segmentation nonsense.
*   **Interrupts**: Full IDT setup. I remapped the PIC because IBM made questionable decisions in the 80s.
*   **Graphics**: Custom VGA drivers. 
    *   **Text Mode**: 80x25 with hardware cursor handling.
    *   **Graphics Mode**: 320x200 (Mode 13h) with a custom font renderer because BIOS interrupts don't work in protected mode.
*   **Input**: PS/2 Keyboard driver with a ring buffer. It handles Shift, Caps Lock, and doesn't crash when you type too fast.
*   **Filesystem**: A virtual in-memory filesystem. It forgets everything when you reboot. It's a feature, not a bug (security!).

## Memory Map (Don't touch this unless you like crashing)

| Address | What's there |
| :--- | :--- |
| `0x00007C00` | **Bootloader**. The BIOS puts us here. We get out fast. |
| `0x00001000` | **Stage 2 Loader**. Sets up the environment for the big boy kernel. |
| `0x00010000` | **Kernel Entry**. The actual OS code lives here. |
| `0x00090000` | **Stack**. Grows down. Don't overflow it. |
| `0x000A0000` | **VGA Memory**. Graphics mode writes here. |
| `0x000B8000` | **Video Memory**. Text mode writes here. |
| `0x00100000` | **Heap**. 1MB of free real estate for `malloc`. |

## How to Build (If you dare)

You need **NASM** and **QEMU**. If you don't know what those are, you're in the wrong repo.

1.  **Compile everything:**
    `cmd
    .\build.bat
    ` 
    This mashes all the assembly files into a 1.44MB floppy image called `j3kOS.img`.

2.  **Boot it:**
    `cmd
    .\test.bat
    ` 
    Launches QEMU. If it crashes, it's probably your fault.

## Shell Commands

The shell is simple. It parses strings and jumps to code. It's not bash, but it works.

**The Basics:**
*   `help`: Lists commands. Obviously.
*   `clear`: Wipes the screen.
*   `reboot`: Triple faults the CPU to restart. Elegant.
*   `mem`: Dumps memory stats. Proves malloc works.
*   `pci`: Scans the PCI bus. Lists devices QEMU is faking.

**The Fun Stuff:**
*   `snake`: A full Snake game. Written in assembly. Yes, really.
*   `gfx`: Demos the graphics primitives (lines, rects, sprites).
*   `gui`: An experimental windowing system. It has a mouse cursor.
*   `edit <file>`: A text editor. It's like Vim but with fewer features and more bugs.

## Project Structure

*   `boot.asm`: The first 512 bytes. Magic happens here.
*   `loader.asm`: Prepares the CPU for 32-bit mode.
*   `kernel32.asm`: The brain. IDT, ISRs, and the shell loop.
*   `graphics.asm`: Direct VGA register manipulation. Painful to write, beautiful to watch.
*   `snake.asm`: The game logic. 
*   `gui.asm`: Mouse driver and window rendering.

## License

MIT. Steal this code. Learn from it. Claim you wrote it. I don't care. Just don't blame me if it bricks your toaster.
