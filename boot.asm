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

    ; say hi
    mov si, msg_welcome
    call print_string

    ; load the actual kernel n shit
    call load_second_stage

    ; yeet to stage 2
    jmp 0x0000:0x1000

; ========================================
; DISK LOADING - READ SHIT FROM DISK
; ========================================
load_second_stage:
    ; load the loader from disk lmao
    mov si, msg_loading
    call print_string
    
    mov ah, 0x02        ; read some fucking sectors
    mov al, 10          ; grab 10 of these bad boys
    mov ch, 0           ; cylinder whatever tf that is
    mov cl, 2           ; start at sector 2
    mov dh, 0           ; head 0 idk
    mov dl, [boot_drive]; disk we booted from
    mov bx, 0x1000      ; dump it at 0x1000
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
    xor bx, bx
    int 0x10
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
msg_welcome:    db 'j3kOS v1.0 by Jortboy3k', 13, 10
                db '@jortboy3k', 13, 10, 0
msg_loading:    db 'Loading...', 0
msg_ok:         db 'OK', 13, 10, 0
msg_disk_err:   db 'DISK ERR', 13, 10, 0
msg_halt:       db 'HALT', 0

boot_drive:     db 0

; ========================================
; BOOT SIGNATURE
; ========================================
times 510-($-$$) db 0
dw 0xAA55