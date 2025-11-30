; j3kOS Protected Mode Loader
; this shit loads the 32-bit kernel and does the pmode switch
; by jortboy3k (@jortboy3k)

[BITS 16]
[ORG 0x1000]

start:
    ; save the boot drive cuz we need it
    mov [boot_drive], dl
    
    ; clear screen
    mov ax, 0x0003
    int 0x10
    
    ; show boot menu
    call show_boot_menu
    
    ; clear screen again before loading
    mov ax, 0x0003
    int 0x10
    
    ; tell em we're loading
    mov si, msg_loading
    call print_string
    
    ; load the actual 32-bit kernel from disk
    ; QEMU floppy geometry: 18 sectors/track, 2 heads, 80 cylinders
    ; Read entire kernel in one go using LBA-style sequential reads
    ; Total: 72 sectors starting at sector 12 (36KB kernel - TESTING)
    
    ; DEBUG: Show we're starting disk read
    mov si, msg_debug_read1
    call print_string
    
    ; Strategy: Try reading only 72 sectors as a test
    ; This is known to work from previous testing
    
    ; Read 72 sectors starting at sector 12
    mov ah, 0x02
    mov al, 72
    mov ch, 0           ; cylinder 0
    mov cl, 12          ; sector 12
    mov dh, 0           ; head 0
    mov dl, [boot_drive]
    mov bx, 0x1000
    mov es, bx
    mov bx, 0x0000      ; ES:BX = 0x10000
    int 0x13
    jc disk_error_1
    
    mov si, msg_debug_read1_ok
    call print_string
    
    ; DEBUG: Enabling A20
    mov si, msg_debug_a20
    call print_string
    
    ; enable a20 line so we can access all the fucking memory
    call enable_a20
    
    ; DEBUG: Loading GDT
    mov si, msg_debug_gdt
    call print_string
    
    ; load the GDT you cuck
    lgdt [gdt_descriptor]
    
    ; DEBUG: Entering protected mode
    mov si, msg_debug_pmode
    call print_string
    
    ; flip the switch to protected mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    ; yeet into 32-bit land
    jmp 0x08:protected_mode_entry

disk_error_1:
    mov si, msg_disk_error_1
    call print_string
    ; Show error code
    mov al, ah
    call print_hex_byte
    call print_newline
    cli
    hlt

disk_error_2:
    mov si, msg_disk_error_2
    call print_string
    ; Show error code
    mov al, ah
    call print_hex_byte
    call print_newline
    cli
    hlt

disk_error:
    mov si, msg_disk_error
    call print_string
    cli
    hlt

; ========================================
; BOOT MENU
; ========================================
show_boot_menu:
    pusha
    
    ; print logo
    mov si, msg_logo
    call print_string
    
    mov si, msg_menu_title
    call print_string
    
    ; print menu options
    mov si, msg_opt1
    call print_string
    mov si, msg_opt2
    call print_string
    mov si, msg_opt3
    call print_string
    
    mov si, msg_prompt
    call print_string
    
    ; start countdown timer
    mov word [countdown], 5
    
.menu_loop:
    ; check for keypress
    mov ah, 0x01
    int 0x16
    jnz .key_pressed
    
    ; wait a bit
    mov cx, 0xFFFF
.delay:
    nop
    loop .delay
    
    ; decrement countdown
    dec word [countdown]
    jnz .menu_loop
    
    ; timeout - boot normally
    jmp .boot_normal

.key_pressed:
    ; read the key
    mov ah, 0x00
    int 0x16
    
    ; check what they pressed
    cmp al, '1'
    je .boot_normal
    cmp al, '2'
    je .boot_safe
    cmp al, '3'
    je .boot_verbose
    cmp al, 13      ; enter
    je .boot_normal
    jmp .menu_loop

.boot_normal:
    mov byte [boot_mode], 0
    jmp .done

.boot_safe:
    mov byte [boot_mode], 1
    mov si, msg_safe_mode
    call print_string
    jmp .done

.boot_verbose:
    mov byte [boot_mode], 2
    mov si, msg_verbose_mode
    call print_string
    jmp .done

.done:
    ; small delay so they can see the message
    mov cx, 0xFFFF
.final_delay:
    nop
    loop .final_delay
    
    popa
    ret

countdown: dw 5
boot_mode: db 0     ; 0=normal, 1=safe, 2=verbose

; ========================================
; A20 LINE - WHATEVER TF THIS DOES
; ========================================
enable_a20:
    ; try the easy way first
    mov ax, 0x2401
    int 0x15
    jnc .done
    
    ; fine, do it the hard way with keyboard controller
    call .wait1
    mov al, 0xAD
    out 0x64, al
    
    call .wait1
    mov al, 0xD0
    out 0x64, al
    
    call .wait2
    in al, 0x60
    push ax
    
    call .wait1
    mov al, 0xD1
    out 0x64, al
    
    call .wait1
    pop ax
    or al, 2
    out 0x60, al
    
    call .wait1
    mov al, 0xAE
    out 0x64, al
    
    call .wait1
    
    .done:
        ret
    
    .wait1:
        in al, 0x64
        test al, 2
        jnz .wait1
        ret
    
    .wait2:
        in al, 0x64
        test al, 1
        jz .wait2
        ret

; ========================================
; HELPER SHIT
; ========================================
print_string:
    pusha
    mov ah, 0x0E
    .loop:
        lodsb
        test al, al
        jz .done
        int 0x10
        jmp .loop
    .done:
        popa
        ret

print_hex_byte:
    ; AL = byte to print in hex
    pusha
    push ax
    
    ; Print high nibble
    shr al, 4
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jle .high_digit
    add al, 7
.high_digit:
    mov ah, 0x0E
    int 0x10
    
    ; Print low nibble
    pop ax
    push ax
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jle .low_digit
    add al, 7
.low_digit:
    mov ah, 0x0E
    int 0x10
    
    pop ax
    popa
    ret

print_newline:
    pusha
    mov ah, 0x0E
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
    popa
    ret

; ========================================
; MESSAGES
; ========================================
msg_logo:       db 10, '     _  ____  _    ____   _____ ', 10
                db '    | ||___ \\| |  / __ \\ / ____|', 10
                db '    | |  __) | | | |  | | (___  ', 10
                db '    | | |__ <| | | |  | |\\___ \\ ', 10
                db ' |__/ | ___) | |_| |__| |____) |', 10
                db ' \\____/|____/|_(_)\\____/|_____/ ', 10, 10, 0

msg_menu_title: db '    boot menu', 10, 10, 0
msg_opt1:       db '    [1] normal boot', 10, 0
msg_opt2:       db '    [2] safe mode', 10, 0
msg_opt3:       db '    [3] verbose boot', 10, 10, 0
msg_prompt:     db '    press 1-3 or wait 5 sec...', 10, 0
msg_safe_mode:  db 10, '    booting in safe mode...', 10, 0
msg_verbose_mode: db 10, '    verbose mode enabled...', 10, 0

msg_loading:    db 'loading kernel...', 10, 0
msg_disk_error: db 'disk read error!', 10, 0
msg_disk_error_1: db 'ERROR: Disk read 1 failed! Code: ', 0
msg_disk_error_2: db 'ERROR: Disk read 2 failed! Code: ', 0

; Debug messages
msg_debug_read1:    db 'DEBUG: Reading 72 sectors @ 0x10000 (TEST)...', 10, 0
msg_debug_read1_ok: db 'DEBUG: Read OK (36KB loaded - partial kernel)', 10, 0
msg_debug_a20:      db 'DEBUG: Enabling A20...', 10, 0
msg_debug_gdt:      db 'DEBUG: Loading GDT...', 10, 0
msg_debug_pmode:    db 'DEBUG: Entering protected mode...', 10, 0

boot_drive: db 0

; ========================================
; GDT - FLAT MEMORY MODEL BABYYYY
; ========================================
align 8
gdt_start:
    ; null descriptor (required for some reason)
    dq 0

gdt_code:
    ; code segment: 4GB flat, ring 0
    dw 0xFFFF       ; limit low
    dw 0x0000       ; base low
    db 0x00         ; base mid
    db 0x9A         ; access: present, ring 0, code, readable
    db 0xCF         ; flags: 4KB gran, 32-bit
    db 0x00         ; base high

gdt_data:
    ; data segment: 4GB flat, ring 0
    dw 0xFFFF       ; limit low
    dw 0x0000       ; base low
    db 0x00         ; base mid
    db 0x92         ; access: present, ring 0, data, writable
    db 0xCF         ; flags: 4KB gran, 32-bit
    db 0x00         ; base high

gdt_user_code:
    ; user code segment: 4GB flat, ring 3
    dw 0xFFFF       ; limit low
    dw 0x0000       ; base low
    db 0x00         ; base mid
    db 0xFA         ; access: present, ring 3, code, readable
    db 0xCF         ; flags: 4KB gran, 32-bit
    db 0x00         ; base high

gdt_user_data:
    ; user data segment: 4GB flat, ring 3
    dw 0xFFFF       ; limit low
    dw 0x0000       ; base low
    db 0x00         ; base mid
    db 0xF2         ; access: present, ring 3, data, writable
    db 0xCF         ; flags: 4KB gran, 32-bit
    db 0x00         ; base high

gdt_tss:
    ; TSS descriptor
    dw 103          ; limit (104 bytes - 1)
    dw 0x0000       ; base low (will be set by kernel)
    db 0x00         ; base mid
    db 0x89         ; access: present, ring 0, TSS available
    db 0x00         ; flags
    db 0x00         ; base high

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; Size
    dd gdt_start                 ; Offset

; ========================================
; 32-BIT ENTRY - WE'RE IN PMODE NOW BITCH
; ========================================
[BITS 32]
protected_mode_entry:
    ; set up all segments for flat memory
    mov ax, 0x10        ; data segment
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000    ; stack at 576KB
    
    ; store boot_mode at 0x7E00 for kernel
    mov al, [boot_mode]
    mov byte [0x7E00], al
    
    ; jump to the actual kernel
    jmp 0x08:0x10000

; ========================================
; DATA
; ========================================
[BITS 16]

; Padding
times 5120-($-$$) db 0  ; Pad to 10 sectors (5KB)
