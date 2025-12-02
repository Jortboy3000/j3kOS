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
    
    ; show startup header
    mov si, msg_startup
    call print_string
    
    ; mov si, msg_stage2
    ; call print_string
    
    ; DEBUG: Show we got here
    ; mov si, msg_debug_start
    ; call print_string
    
    ; tell em we're loading
    mov si, msg_loading
    call print_string
    
    ; Modern approach: Use LBA mode (INT 13h AH=42)
    ; No CHS geometry bullshit, just absolute sector numbers
    ; Kernel is 36 sectors starting at LBA sector 12
    
    ; Check if LBA is supported
    ; mov si, msg_check_lba
    ; call print_string
    
    ; Save boot drive
    mov al, [boot_drive]
    mov [temp_drive], al
    
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .no_lba_support
    
    ; Check magic
    ; mov si, msg_check_magic
    ; call print_string
    cmp bx, 0xAA55
    jne .bad_magic
    ; mov si, msg_ok
    ; call print_string
    
    ; Check DAP support
    ; mov si, msg_check_dap
    ; call print_string
    test cl, 1
    jz .no_dap
    ; mov si, msg_ok
    ; call print_string
    jmp .lba_ok
    
.no_lba_support:
    mov si, msg_no_lba
    call print_string
    mov si, msg_error_code
    call print_string
    mov al, ah
    call print_hex_byte
    call print_newline
    jmp halt_system
    
.bad_magic:
    mov si, msg_fail
    call print_string
    mov si, msg_bad_magic
    call print_string
    mov ax, bx
    call print_hex_word
    call print_newline
    jmp halt_system
    
.no_dap:
    mov si, msg_fail
    call print_string
    mov si, msg_no_dap_support
    call print_string
    mov al, cl
    call print_hex_byte
    call print_newline
    jmp halt_system
    
.lba_ok:
    ; Step 1: Read kernel header (first sector) to get actual kernel size
    ; This allows dynamic kernel loading without hardcoded sector counts
    ; mov si, msg_reading_header
    ; call print_string
    
    ; Setup DAP to read 1 sector (kernel header)
    mov word [dap_sectors], 1
    mov word [dap_offset], 0x0000
    mov word [dap_segment], 0x1000    ; Load header to 0x10000
    mov dword [dap_lba_low], 11       ; Kernel starts at LBA 11
    mov dword [dap_lba_high], 0
    
    ; Execute read
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, disk_address_packet
    int 0x13
    jc disk_error_header
    
    ; Verify kernel magic signature (J3KO = 0x4A334B4F)
    ; We loaded the kernel to segment 0x1000 (physical 0x10000)
    ; We must use ES to access it because DS=0 and 0x10000 is not addressable with 16-bit offset
    ; mov si, msg_verify_magic
    ; call print_string
    
    push es
    mov ax, 0x1000
    mov es, ax
    mov eax, [es:0x0000]    ; Read magic from 0x1000:0x0000
    pop es
    
    cmp eax, 0x4A334B4F     ; Check if it matches "J3KO"
    jne kernel_magic_error
    
    ; mov si, msg_magic_ok
    ; call print_string
    
    ; Read kernel size from header
    push es
    mov ax, 0x1000
    mov es, ax
    mov eax, [es:0x0004]    ; Read size from 0x1000:0x0004
    pop es
    
    mov [kernel_size], eax
    
    ; Calculate sectors needed (size + 511) / 512
    add eax, 511
    shr eax, 9              ; Divide by 512
    mov [kernel_sectors], ax
    
    ; Show kernel info
    ; mov si, msg_kernel_size
    ; call print_string
    ; mov eax, [kernel_size]
    ; call print_hex_dword
    ; mov si, msg_bytes
    ; call print_string
    
    ; mov si, msg_kernel_sectors
    ; call print_string
    ; mov ax, [kernel_sectors]
    ; call print_hex_word
    ; mov si, msg_sectors_text
    ; call print_string
    
    ; Validate kernel size (max 512KB = 1024 sectors for safety)
    cmp word [kernel_sectors], 1024
    ja kernel_size_error
    
    ; =================================================================
    ; GENERIC KERNEL LOADING LOOP
    ; Loads kernel of ANY size (up to 512KB) in 18-sector chunks
    ; =================================================================
    
    ; mov si, msg_debug_load_loop
    ; call print_string
    
    ; Initialize variables
    mov ax, 11                  ; Start LBA (Kernel starts at 11)
    mov [current_lba_var], ax
    
    mov ax, [kernel_sectors]    ; Total sectors to read
    mov [sectors_left], ax
    
    mov ax, 0x1000              ; Start Segment (0x10000 physical)
    mov [current_segment], ax
    
.load_loop:
    ; Check if we are done
    cmp word [sectors_left], 0
    je .kernel_loaded_label
    
    ; Calculate sectors for this pass (max 18)
    mov ax, [sectors_left]
    cmp ax, 18
    jbe .set_count
    mov ax, 18
.set_count:
    mov [sectors_to_read], ax
    
    ; Setup DAP
    mov ax, [sectors_to_read]
    mov word [dap_sectors], ax
    mov word [dap_offset], 0x0000     ; Always offset 0
    mov ax, [current_segment]
    mov word [dap_segment], ax
    mov eax, 0
    mov ax, [current_lba_var]
    mov dword [dap_lba_low], eax      ; Set LBA
    mov dword [dap_lba_high], 0
    
    ; Visual feedback (dots)
    mov al, '.'
    call print_char
    
    ; Execute Read
    mov ah, 0x42
    mov dl, [boot_drive]
    mov si, disk_address_packet
    int 0x13
    jc .disk_error_loop
    
    ; Update variables for next pass
    
    ; 1. Update LBA
    mov ax, [sectors_to_read]
    add [current_lba_var], ax
    
    ; 2. Update Sectors Left
    mov ax, [sectors_left]
    sub ax, [sectors_to_read]
    mov [sectors_left], ax
    
    ; 3. Update Segment
    ; Each sector is 512 bytes = 32 paragraphs (0x20)
    ; Segment += Sectors * 32
    mov ax, [sectors_to_read]
    shl ax, 5                   ; Multiply by 32
    add [current_segment], ax
    
    jmp .load_loop

.disk_error_loop:
    mov si, msg_fail
    call print_string
    mov si, msg_error_load
    call print_string
    jmp halt_system

    ; =================================================================
    ; END LOAD LOOP
    ; =================================================================

.kernel_loaded_label:
    ; mov si, msg_ok
    ; call print_string
    ; mov si, msg_kernel_loaded
    ; call print_string
    
    ; DEBUG: Enabling A20
    ; mov si, msg_debug_a20
    ; call print_string
    
    ; enable a20 line so we can access all the fucking memory
    call enable_a20
    
    ; Verify A20 is actually enabled
    call check_a20
    test ax, ax
    jz .a20_failed
    
    ; mov si, msg_a20_ok
    ; call print_string
    jmp .gdt_setup

.a20_failed:
    mov si, msg_fail
    call print_string
    mov si, msg_error_a20
    call print_string
    jmp halt_system

.gdt_setup:
    ; DEBUG: Loading GDT
    ; mov si, msg_debug_gdt
    ; call print_string
    
    ; load the GDT you cuck
    lgdt [gdt_descriptor]
    
    ; mov si, msg_gdt_ok
    ; call print_string
    
    ; DEBUG: Entering protected mode
    ; mov si, msg_debug_pmode
    ; call print_string
    
    ; --- ENTER PROTECTED MODE THE RIGHT WAY ---
    cli                          ; no more interrupts
    lgdt [gdt_descriptor]        ; load GDT (already done, but ensure it's set)
    
    mov eax, cr0
    or  al, 1                    ; set PE bit
    mov cr0, eax
    
    ; IMMEDIATELY jump to 32-bit code — DO NOT TOUCH BIOS OR REAL-MODE STUFF AFTER THIS
    jmp 0x08:protected_mode_entry_32

disk_error_header:
    mov si, msg_fail
    call print_string
    mov si, msg_error_header
    call print_string
    mov al, ah
    call print_hex_byte
    call print_newline
    jmp halt_system

kernel_magic_error:
    mov si, msg_fail
    call print_string
    mov si, msg_error_magic
    call print_string
    
    push es
    mov ax, 0x1000
    mov es, ax
    mov eax, [es:0x0000]
    pop es
    
    call print_hex_dword
    call print_newline
    mov si, msg_expected_magic
    call print_string
    jmp halt_system

kernel_size_error:
    mov si, msg_fail
    call print_string
    mov si, msg_error_size
    call print_string
    mov ax, [kernel_sectors]
    call print_hex_word
    call print_newline
    jmp halt_system

disk_error_chunk1:
    mov si, msg_fail
    call print_string
    ; mov si, msg_error_chunk1
    call print_string
    mov al, ah
    call print_hex_byte
    call print_newline
    mov si, msg_dap_details
    call print_string
    mov si, msg_lba_val
    call print_string
    mov ax, word [dap_lba_low]
    call print_hex_word
    call print_newline
    mov si, msg_seg_val
    call print_string
    mov ax, word [dap_segment]
    call print_hex_word
    mov al, ':'
    call print_char
    mov ax, word [dap_offset]
    call print_hex_word
    call print_newline
    jmp halt_system

disk_error_chunk2:
    mov si, msg_fail
    call print_string
    ; mov si, msg_error_chunk2
    call print_string
    mov al, ah
    call print_hex_byte
    call print_newline
    mov si, msg_dap_details
    call print_string
    mov si, msg_lba_val
    call print_string
    mov ax, word [dap_lba_low]
    call print_hex_word
    call print_newline
    mov si, msg_seg_val
    call print_string
    mov ax, word [dap_segment]
    call print_hex_word
    mov al, ':'
    call print_char
    mov ax, word [dap_offset]
    call print_hex_word
    call print_newline
    jmp halt_system

halt_system:
    mov si, msg_system_halted
    call print_string
    cli
    hlt
    jmp halt_system

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

check_a20:
    push ds
    push es
    push di
    push si
    
    cli
    
    xor ax, ax
    mov es, ax
    mov di, 0x0500
    
    not ax
    mov ds, ax
    mov si, 0x0510
    
    mov al, byte [es:di]
    push ax
    
    mov al, byte [ds:si]
    push ax
    
    mov byte [es:di], 0x00
    mov byte [ds:si], 0xFF
    
    cmp byte [es:di], 0xFF
    
    pop ax
    mov byte [ds:si], al
    
    pop ax
    mov byte [es:di], al
    
    mov ax, 0
    je .exit
    
    mov ax, 1
    
.exit:
    sti
    pop si
    pop di
    pop es
    pop ds
    ret

; ========================================
; HELPER SHIT
; ========================================
print_string:
    pusha
    mov ah, 0x0E
    mov bl, 0x0A    ; bright green text
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

print_hex_word:
    ; AX = word to print in hex
    pusha
    push ax
    mov al, ah
    call print_hex_byte
    pop ax
    call print_hex_byte
    popa
    ret

print_hex_dword:
    ; EAX = dword to print in hex
    pusha
    push eax
    shr eax, 16
    call print_hex_word
    pop eax
    call print_hex_word
    popa
    ret

print_char:
    ; AL = char to print
    pusha
    mov ah, 0x0E
    int 0x10
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

; Disk Address Packet for LBA reads (INT 13h AH=42)
align 4
disk_address_packet:
    db 0x10             ; size of packet (16 bytes)
    db 0                ; always 0
dap_sectors: dw 0       ; number of sectors to read
dap_offset:  dw 0       ; offset
dap_segment: dw 0       ; segment
dap_lba_low: dd 0       ; lower 32 bits of LBA
dap_lba_high: dd 0      ; upper 32 bits of LBA

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
protected_mode_entry_32:
    ; set up all segments for flat memory
    mov ax, 0x10        ; data segment
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000    ; stack at 576KB
    
    ; Optional: Write "Protected Mode OK" directly to VGA memory
    ; mov edi, 0xB8000 + (160 * 10)  ; Row 10
    ; mov esi, hello_pm
    ; mov ah, 0x0A          ; bright green on black
; .next:
    ; lodsb
    ; test al, al
    ; jz .done
    ; mov [edi], ax
    ; add edi, 2
    ; jmp .next
; .done:
    
    ; Verify kernel magic one last time before jumping
    ; Note: We are in 32-bit mode now, so [0x10000] is valid!
    mov eax, [0x10000]
    cmp eax, 0x4A334B4F
    jne .pmode_magic_fail
    
    ; jump to the actual kernel (skip 16-byte header)
    ; Header is 16 bytes: Magic(4) + Size(4) + Version(4) + Reserved(4)
    jmp 0x08:0x10010

.pmode_magic_fail:
    ; Write "BAD KERNEL MAGIC" to screen in red
    mov edi, 0xB8000 + (160 * 12)  ; Row 12
    mov esi, msg_pm_fail
    mov ah, 0x0C          ; bright red on black
.fail_loop:
    lodsb
    test al, al
    jz .halt_pm
    mov [edi], ax
    add edi, 2
    jmp .fail_loop
.halt_pm:
    hlt
    jmp .halt_pm

hello_pm: db '>>> j3kOS now in 32-bit protected mode <<<', 0
msg_pm_fail: db 'FATAL: Kernel magic corrupted in Protected Mode!', 0

; ========================================
; DATA
; ========================================
[BITS 16]

; Boot drive storage
boot_drive: db 0
temp_drive: db 0

; Kernel loading variables
kernel_size: dd 0
kernel_sectors: dw 0
current_lba_var: dw 0
sectors_left: dw 0
sectors_to_read: dw 0
current_segment: dw 0

; Messages
msg_startup: db 10, '                  ======================================', 10
             db '                        j3kOS Loader v2.3            ', 10
             db '                  ======================================', 10, 0
msg_stage2: db '                        Stage 2 Bootloader Loaded', 10, 0
msg_loading: db '                  Loading system...', 0
msg_reading_header: db '[1/5] Reading kernel header...', 0
msg_verify_magic: db '[2/5] Verifying kernel signature...', 0
msg_magic_ok: db ' OK (J3KO)', 10, 0
msg_kernel_size: db '[3/5] Kernel size: ', 0
msg_bytes: db ' bytes', 10, 0
msg_kernel_sectors: db '      Sectors needed: ', 0
msg_sectors_text: db ' sectors', 10, 0
msg_debug_chunk1: db '[4/5] Loading kernel chunk 1...', 0
msg_debug_chunk2: db '[5/5] Loading kernel chunk 2...', 0
msg_kernel_loaded: db 'Kernel load complete!', 10, 0

; Error messages
msg_error_header: db '[FATAL] Failed to read kernel header! Error: 0x', 0
msg_error_magic: db '[FATAL] Invalid kernel magic! Found: 0x', 0
msg_expected_magic: db '        Expected: 0x4A334B4F (J3KO)', 10
                    db '        Kernel may be corrupted or incompatible.', 10, 0
msg_error_size: db '[FATAL] Kernel too large! Sectors: 0x', 0
msg_error_load: db '[FATAL] Disk read error during load loop!', 10, 0
msg_error_a20: db '[FATAL] A20 line verification failed!', 10, 0
msg_skip_check: db ' [DEBUG] SKIPPING MAGIC CHECK...', 10, 0

; Rest of messages...
msg_check_lba: db 'Checking LBA support...', 0
msg_check_magic: db 'Verifying BIOS magic...', 0
msg_check_dap: db 'Checking DAP support...', 0
msg_dap_setup: db ' DAP configured...', 0
msg_ok: db ' OK', 10, 0
msg_fail: db ' FAIL', 10, 0
msg_warn_zero: db '  [WARN] Read returned zeros at 0x10000', 10, 0
msg_debug_start: db '[DEBUG] Loader entry point reached', 10, 0
msg_debug_load_loop: db '[4/5] Loading kernel sectors...', 0
msg_debug_a20: db 'Enabling A20 line...', 0
msg_a20_ok: db ' OK', 10, 0
msg_debug_gdt: db 'Loading GDT...', 0
msg_gdt_ok: db ' OK', 10, 0
msg_debug_pmode: db 'Entering protected mode...', 10, 0
msg_no_lba: db '[FATAL] LBA not supported! Need modern BIOS', 10, 0
msg_bad_magic: db '[FATAL] BIOS magic check failed! BX: 0x', 0
msg_no_dap: db '[FATAL] DAP not supported! Feature bits: 0x', 0
msg_dap_details: db '  DAP Details:', 10, 0
msg_lba_val: db '    LBA: 0x', 0
msg_seg_val: db '    Destination: 0x', 0
msg_error_code: db ' Error code: 0x', 0
msg_no_dap_support: db '[FATAL] DAP not supported! Feature bits: 0x', 0
msg_system_halted: db 10, '[HALT] System halted. Reboot required.', 10, 0

; Padding
times 5120-($-$$) db 0  ; Pad to 10 sectors (5KB)
