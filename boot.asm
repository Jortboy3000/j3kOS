; j3kOS bootloader - this fucking thing boots the OS
; BIOS loads this shit at 0x7C00
; by jortboy3k (@jortboy3k)

BITS 16
ORG 0x7C00

; ========================================
; BOOT SECTOR - WHERE THE MAGIC HAPPENS
; ========================================
start:
    ; fuck around with segments and shit
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00      ; stack goes down you cuck
    mov [boot_drive], dl ; save this shit for later
    sti

    ; clear the screen cuz why not
    mov ah, 0x00
    mov al, 0x03
    int 0x10
    
    ; set text color to bright cyan on black for visibility
    mov ah, 0x09
    mov al, ' '
    mov bh, 0
    mov bl, 0x0B    ; bright cyan
    mov cx, 2000    ; fill screen
    int 0x10

    ; say hi with some style
    mov si, msg_banner
    call print_string
    
    mov si, msg_welcome
    call print_string
    
    mov si, msg_author
    call print_string
    
    mov si, msg_separator
    call print_string
    
    ; small delay so you can see the banner
    call delay

    ; load the actual kernel n shit
    call load_second_stage
    
    ; another delay
    call delay

    ; yeet to stage 2
    jmp 0x0000:0x1000

; ========================================
; DISK LOADING - READ SHIT FROM DISK
; ========================================
load_second_stage:
    ; load the loader from disk lmao
    mov si, msg_loading
    call print_string
    
    ; Simple read - bootloader must be small
    mov ah, 0x02        ; read sectors
    mov al, 10          ; 10 sectors
    mov ch, 0           ; cylinder 0
    mov cl, 2           ; sector 2
    mov dh, 0           ; head 0
    mov dl, [boot_drive]
    mov bx, 0x1000      ; load at 0x1000
    int 0x13
    
    jc .error
    
    mov si, msg_ok
    call print_string
    ret
    
.error:
    mov si, msg_disk_err
    call print_string
    jmp halt

; ========================================
; UTILITY SHIT
; ========================================
print_string:
    ; print whatever string SI points to
    .loop:
        lodsb
        test al, al
        jz .done
        call print_char
        jmp .loop
    .done:
        ret

print_char:
    ; print one char, simple af
    mov ah, 0x0E
    mov bl, 0x0B    ; bright cyan text
    int 0x10
    ret

delay:
    ; simple delay loop
    push cx
    mov cx, 0xFFFF
    .loop:
        nop
        nop
        loop .loop
    pop cx
    ret

halt:
    mov si, msg_halt
    call print_string
    cli
    hlt
    jmp halt

; ========================================
; DATA N SHIT
; ========================================
msg_banner:     db 13, 10
                db '  _____ _    ___  _____ ', 13, 10
                db ' |___ /| | _/ _ \/ ____|', 13, 10
                db '   |_ \| |/ | | | (___ ', 13, 10
                db '  ___) |   <| |_| |\___ \', 13, 10
                db ' |____/|_|\_\\___/ |____/', 13, 10, 13, 10, 0
msg_welcome:    db '  Operating System v1.0', 13, 10, 0
msg_author:     db '  by Jortboy3k (@jortboy3k)', 13, 10, 0
msg_separator:  db '  ------------------------', 13, 10, 13, 10, 0
msg_loading:    db '  [BOOT] Loading stage 2...', 0
msg_ok:         db ' OK', 13, 10, 0
msg_disk_err:   db ' FAIL', 13, 10, '  [ERROR] Disk read failed!', 13, 10, 0
msg_halt:       db '  [HALT] System stopped.', 13, 10, 0

boot_drive:     db 0

; ========================================
; BOOT SIGNATURE
; ========================================
times 510-($-$$) db 0
dw 0xAA55