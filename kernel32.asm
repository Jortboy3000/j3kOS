; j3kOS 32-bit Kernel
; the actual OS, runs in protected mode
; by jortboy3k (@jortboy3k)

[BITS 32]
[ORG 0x10000]

; ========================================
; KERNEL HEADER - For dynamic loading
; ========================================
kernel_header:
    dd 0x4A334B4F           ; Magic: "J3KO" (j3kOS signature)
    dd 0x00000000           ; Kernel size in bytes (will be set by build script)
    dd 0x00000001           ; Version: 1.0
    dd 0x00000000           ; Reserved for future use

; ========================================
; KERNEL ENTRY - LET'S FUCKING GO
; ========================================
kernel_start:
    ; read boot_mode from loader
    mov al, [0x7E00]
    mov [boot_mode], al
    
    call clear_screen
    
    mov esi, msg_boot
    call print_string
    
    ; show boot mode if not normal
    cmp byte [boot_mode], 0
    je .skip_mode_msg
    cmp byte [boot_mode], 1
    je .safe_mode
    mov esi, msg_verbose_mode
    jmp .show_mode
.safe_mode:
    mov esi, msg_safe_mode
.show_mode:
    call print_string
.skip_mode_msg:
    
    call init_idt
    cmp byte [boot_mode], 2
    jne .skip_idt_msg
    mov esi, msg_init_idt_ok
    call print_string
.skip_idt_msg:
    
    call init_pic
    cmp byte [boot_mode], 2
    jne .skip_pic_msg
    mov esi, msg_init_pic_ok
    call print_string
.skip_pic_msg:
    
    call init_pit
    cmp byte [boot_mode], 2
    jne .skip_pit_msg
    mov esi, msg_init_pit_ok
    call print_string
.skip_pit_msg:
    
    call init_keyboard
    cmp byte [boot_mode], 2
    jne .skip_kb_msg
    mov esi, msg_init_kb_ok
    call print_string
.skip_kb_msg:
    
    call init_tss
    cmp byte [boot_mode], 2
    jne .skip_tss_msg
    mov esi, msg_init_tss_ok
    call print_string
.skip_tss_msg:
    
    call init_page_mgmt
    cmp byte [boot_mode], 2
    jne .skip_page_msg
    mov esi, msg_init_page_ok
    call print_string
.skip_page_msg:
    
    call vmm_init               ; Initialize virtual memory manager
    
    ; Enable the cool cursor
    call enable_cursor
    
    sti
    
    ; skip sound in safe mode
    cmp byte [boot_mode], 1
    je .skip_sound
    call play_startup_sound
.skip_sound:
    
    call clear_screen
    
    mov esi, msg_boot
    call print_string
    
    call login_main
    
    mov esi, msg_ready
    call print_string
    
    ; Try to mount filesystem
    mov esi, msg_mounting
    call print_string
    call mount_j3kfs
    
    call shell_main
    
    cli
    hlt

; ========================================
; INCLUDES
; ========================================
%include "kernel/video.asm"
%include "kernel/utils.asm"
%include "kernel/idt.asm"
%include "drivers/pic.asm"
%include "drivers/pit.asm"
%include "drivers/keyboard.asm"
%include "kernel/tasks.asm"
%include "kernel/memory.asm"
%include "drivers/disk.asm"
%include "kernel/vmm.asm"
%include "kernel/syscalls.asm"
%include "kernel/login.asm"
%include "kernel/shell.asm"
%include "kernel/j3kfs.asm"
%include "kernel/swap_system.asm"
%include "kernel/editor.asm"
%include "kernel/snake.asm"

%include "drivers/rtc.asm"
%include "drivers/pci.asm"
%include "drivers/rtl8139.asm"
%include "drivers/network.asm"
%include "drivers/graphics.asm"
%include "drivers/gui.asm"
%include "drivers/sound.asm"

; ========================================
; DATA
; ========================================
msg_boot            db "j3kOS 32-bit Protected Mode",10
                    db "by Jortboy3k (@jortboy3k) - Western Sydney Rep",10,10,0
msg_safe_mode       db "[SAFE MODE]",10,0
msg_verbose_mode    db "[VERBOSE MODE]",10,0
msg_init_idt_ok     db "[INIT] IDT OK",10,0
msg_init_pic_ok     db "[INIT] PIC OK",10,0
msg_init_pit_ok     db "[INIT] PIT OK",10,0
msg_init_kb_ok      db "[INIT] Keyboard OK",10,0
msg_init_tss_ok     db "[INIT] TSS OK",10,0
msg_init_page_ok    db "[INIT] Page Mgmt OK",10,0
msg_ready           db "System ready. Type 'help' if you're lost lad.",10,10,0
msg_mounting        db "Mounting filesystem...",10,0
