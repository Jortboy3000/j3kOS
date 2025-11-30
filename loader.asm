; j3kOS Protected Mode Loader
; this shit loads the 32-bit kernel and does the pmode switch
; by jortboy3k (@jortboy3k)

[BITS 16]
[ORG 0x1000]

start:
    ; save the boot drive cuz we need it
    mov [boot_drive], dl
    
    ; clear screen again
    mov ax, 0x0003
    int 0x10
    
    ; tell em we're loading
    mov si, msg_loading
    call print_string
    
    ; load the actual 32-bit kernel from disk
    ; sector 12, grab 80 sectors to 0x10000
    mov ah, 0x02        ; read sectors
    mov al, 80          ; 80 sectors worth of kernel (40KB)
    mov ch, 0           ; cylinder 0
    mov cl, 12          ; sector 12
    mov dh, 0           ; head 0
    mov dl, [boot_drive]
    mov bx, 0x1000
    mov es, bx
    mov bx, 0x0000      ; ES:BX = 0x10000 do the math
    int 0x13
    jc disk_error
    
    ; enable a20 line so we can access all the fucking memory
    call enable_a20
    
    ; load the GDT you cuck
    lgdt [gdt_descriptor]
    
    ; flip the switch to protected mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    ; yeet into 32-bit land
    jmp 0x08:protected_mode_entry

disk_error:
    mov si, msg_disk_error
    call print_string
    cli
    hlt

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
    
    ; jump to the actual kernel
    jmp 0x10000

; ========================================
; DATA
; ========================================
[BITS 16]
boot_drive:     db 0
msg_loading:    db 'Loading kernel...', 13, 10, 0
msg_disk_error: db 'Disk error!', 13, 10, 0

; Padding
times 5120-($-$$) db 0  ; Pad to 10 sectors (5KB)
