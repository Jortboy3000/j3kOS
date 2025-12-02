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
    
    call shell_main
    
    cli
    hlt

; ========================================
; LOGIN - SECURITY THEATER (fake as fuck)
; ========================================
login_username: times 32 db 0
login_password: times 32 db 0
msg_login_prompt: db 'j3kOS Login: ', 0
msg_pass_prompt:  db 'Password: ', 0
msg_login_fail:   db 'Login incorrect.', 10, 0
msg_welcome_user: db 'Welcome, ', 0

login_main:
    .retry:
        mov esi, msg_login_prompt
        call print_string
        
        ; read username (who are you?)
        mov ebx, login_username
        mov ecx, 32
        call read_line
        
        ; check if empty (don't be stupid)
        cmp byte [login_username], 0
        je .retry
        
        mov esi, msg_pass_prompt
        call print_string
        
        ; read password (masked so nobody sees your hunter2)
        mov ebx, login_password
        mov ecx, 32
        call read_line_masked
        
        ; for now, accept anything because I don't care
        
        call print_newline
        mov esi, msg_welcome_user
        call print_string
        mov esi, login_username
        call print_string
        call print_newline
        call print_newline
        
        ret

; Helper to read a line of text because users can't type
read_line:
    ; EBX = buffer, ECX = max len
    pusha
    xor edx, edx    ; count
    
    .loop:
        call getchar_wait
        
        cmp al, 13      ; enter
        je .done
        
        cmp al, 8       ; backspace
        je .backspace
        
        cmp edx, ecx
        jge .loop
        
        mov [ebx + edx], al
        inc edx
        call print_char
        jmp .loop
        
    .backspace:
        test edx, edx
        jz .loop
        dec edx
        dec dword [cursor_x]
        mov al, ' '
        call print_char
        dec dword [cursor_x]
        call update_cursor
        jmp .loop
        
    .done:
        mov byte [ebx + edx], 0
        mov al, 10
        call print_char
        popa
        ret

; Helper to read a line masked (*) - top secret shit
read_line_masked:
    ; EBX = buffer, ECX = max len
    pusha
    xor edx, edx
    
    .loop:
        call getchar_wait
        
        cmp al, 13
        je .done
        
        cmp al, 8       ; backspace
        je .backspace
        
        cmp edx, ecx
        jge .loop
        
        mov [ebx + edx], al
        inc edx
        mov al, '*'
        call print_char
        jmp .loop
        
    .backspace:
        test edx, edx
        jz .loop
        dec edx
        dec dword [cursor_x]
        mov al, ' '
        call print_char
        dec dword [cursor_x]
        call update_cursor
        jmp .loop
        
    .done:
        mov byte [ebx + edx], 0
        mov al, 10
        call print_char
        popa
        ret

; ========================================
; VIDEO OUTPUT - PRINT SHIT TO SCREEN
; ========================================
VIDEO_MEM equ 0xB8000
VGA_WIDTH equ 80
VGA_HEIGHT equ 25
WHITE_ON_BLACK equ 0x0F

cursor_x: dd 0
cursor_y: dd 0
boot_mode: db 0  ; 0=normal, 1=safe, 2=verbose

clear_screen:
    pusha
    mov edi, VIDEO_MEM
    mov ecx, VGA_WIDTH * VGA_HEIGHT
    mov ax, 0x0F20
    rep stosw
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    call update_cursor
    popa
    ret

print_string:
    ; ESI = string to print
    pusha
    .loop:
        lodsb
        test al, al
        jz .done
        call print_char
        jmp .loop
    .done:
        popa
        ret

print_char:
    ; AL = character
    pusha
    
    ; handle newlines
    cmp al, 10
    je .newline
    
    ; figure out where to write in video mem
    mov ebx, [cursor_y]
    imul ebx, VGA_WIDTH
    add ebx, [cursor_x]
    shl ebx, 1
    add ebx, VIDEO_MEM
    
    ; write the char
    mov ah, WHITE_ON_BLACK
    mov [ebx], ax
    
    ; move cursor
    inc dword [cursor_x]
    cmp dword [cursor_x], VGA_WIDTH
    jl .update_cursor_pos
    
    .newline:
        mov dword [cursor_x], 0
        inc dword [cursor_y]
        
        ; scroll if we hit the bottom
        cmp dword [cursor_y], VGA_HEIGHT
        jl .update_cursor_pos
        call scroll_screen
        dec dword [cursor_y]
    
    .update_cursor_pos:
        call update_cursor
    
    .done:
        popa
        ret

scroll_screen:
    pusha
    ; copy all lines up one
    mov edi, VIDEO_MEM
    mov esi, VIDEO_MEM + VGA_WIDTH*2
    mov ecx, VGA_WIDTH * (VGA_HEIGHT-1)
    rep movsw
    
    ; clear the last line
    mov ecx, VGA_WIDTH
    mov ax, 0x0F20
    rep stosw
    popa
    ret

; ========================================
; CURSOR MANAGEMENT - MAKE IT BLINK
; ========================================
enable_cursor:
    pusha
    ; Set cursor shape (scanlines 13-15 = thick block)
    mov dx, 0x3D4
    mov al, 0x0A
    out dx, al
    
    inc dx
    mov al, 13          ; Start scanline
    out dx, al
    
    dec dx
    mov al, 0x0B
    out dx, al
    
    inc dx
    mov al, 15          ; End scanline
    out dx, al
    popa
    ret

update_cursor:
    pusha
    ; Calculate linear position: y * 80 + x
    mov eax, [cursor_y]
    mov ebx, VGA_WIDTH
    mul ebx
    add eax, [cursor_x]
    mov ebx, eax
    
    ; Set low byte
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    
    inc dx
    mov al, bl
    out dx, al
    
    ; Set high byte
    dec dx
    mov al, 0x0E
    out dx, al
    
    inc dx
    mov al, bh
    out dx, al
    
    popa
    ret

print_hex:
    ; EAX = value to print
    pusha
    mov ecx, 8
    .loop:
        rol eax, 4
        push eax
        and eax, 0x0F
        add al, '0'
        cmp al, '9'
        jle .digit
        add al, 7
    .digit:
        call print_char
        pop eax
        loop .loop
    popa
    ret

print_newline:
    ; print a newline character
    pusha
    mov al, 10
    call print_char
    popa
    ret

print_hex_dump:
    ; ESI = buffer, ECX = length (max 256 bytes for display)
    pusha
    push ecx
    
    cmp ecx, 256
    jle .print_loop
    mov ecx, 256
    
.print_loop:
    test ecx, ecx
    jz .done_dump
    
    ; print byte as hex
    lodsb
    movzx eax, al
    push ecx
    push esi
    
    ; print high nibble
    mov cl, al
    shr cl, 4
    and cl, 0x0F
    add cl, '0'
    cmp cl, '9'
    jle .high_digit
    add cl, 7
.high_digit:
    mov al, cl
    call print_char
    
    ; print low nibble
    pop esi
    push esi
    mov al, [esi-1]
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jle .low_digit
    add al, 7
.low_digit:
    call print_char
    
    ; space between bytes
    mov al, ' '
    call print_char
    
    pop esi
    pop ecx
    dec ecx
    
    ; newline every 16 bytes
    mov eax, esi
    sub eax, [esp + 28]
    and eax, 0x0F
    test eax, eax
    jnz .print_loop
    
    call print_newline
    jmp .print_loop
    
.done_dump:
    pop ecx
    call print_newline
    popa
    ret

; ========================================
; IDT - INTERRUPT SHIT
; ========================================
init_idt:
    ; build 256 IDT entries with default handler
    mov edi, idt_table
    mov ecx, 256
    
    .loop:
        ; handler address (low part)
        mov eax, default_isr
        mov [edi], ax
        
        ; code segment selector
        mov word [edi+2], 0x08
        
        ; reserved byte
        mov byte [edi+4], 0
        
        ; type and attributes
        mov byte [edi+5], 0x8E
        
        ; handler address (high part)
        shr eax, 16
        mov [edi+6], ax
        
        add edi, 8
        loop .loop
    
    ; set up our actual interrupt handlers
    ; timer on IRQ0 (INT 0x20)
    mov edi, idt_table + (0x20 * 8)
    mov eax, irq0_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; keyboard on IRQ1 (INT 0x21)
    mov edi, idt_table + (0x21 * 8)
    mov eax, irq1_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; network (RTL8139) on IRQ11 (INT 0x2B)
    mov edi, idt_table + (0x2B * 8)
    mov eax, irq11_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; PS/2 mouse on IRQ12 (INT 0x2C)
    mov edi, idt_table + (0x2C * 8)
    mov eax, irq12_handler
    mov [edi], ax
    shr eax, 16
    mov [edi+6], ax
    
    ; system call on INT 0x80
    mov edi, idt_table + (0x80 * 8)
    mov eax, syscall_handler
    mov [edi], ax
    mov word [edi+2], 0x08      ; kernel code segment
    mov byte [edi+5], 0xEE      ; present, DPL=3 (user), interrupt gate
    shr eax, 16
    mov [edi+6], ax
    
    ; load that shit
    lidt [idt_descriptor]
    ret

default_isr:
    iret

; ========================================
; PIC - REMAP THIS FUCKING THING
; ========================================
init_pic:
    ; ICW1 - initialize both PICs
    mov al, 0x11
    out 0x20, al        ; master
    out 0xA0, al        ; slave
    
    ; ICW2 - set vector offsets
    mov al, 0x20
    out 0x21, al        ; master at 0x20
    mov al, 0x28
    out 0xA1, al        ; slave at 0x28
    
    ; ICW3 - tell em how they're connected
    mov al, 0x04
    out 0x21, al        ; slave on IRQ2
    mov al, 0x02
    out 0xA1, al        ; cascade shit
    
    ; ICW4 - 8086 mode whatever
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    
    ; enable timer, keyboard, IRQ11 (network), and IRQ12 (mouse)
    mov al, 0xFC        ; IRQ0 and IRQ1 enabled
    out 0x21, al
    mov al, 0xF3        ; IRQ11 and IRQ12 enabled (bits 3 and 4 = 0)
    out 0xA1, al
    ret

; ========================================
; PIT - TIMER SHIT (100Hz)
; ========================================
init_pit:
    ; set up the timer for 100Hz
    mov al, 0x36        ; channel 0, rate generator
    out 0x43, al
    
    ; divisor = 1193182 / 100 = 11932
    mov ax, 11932
    out 0x40, al        ; low byte
    mov al, ah
    out 0x40, al        ; high byte
    ret

timer_ticks: dd 0

; ========================================
; RTC (Real-Time Clock) - ACTUAL DATE/TIME
; ========================================

; read a byte from CMOS
; AL = register number
; returns AL = value
read_cmos:
    push ebx
    out 0x70, al    ; select CMOS register
    in al, 0x71     ; read the value
    pop ebx
    ret

; convert BCD to binary
; AL = BCD value
; returns AL = binary value
bcd_to_binary:
    push ebx
    mov bl, al
    and al, 0x0F    ; get lower nibble
    shr bl, 4       ; get upper nibble
    movzx bx, bl
    imul bx, bx, 10 ; upper * 10
    add al, bl      ; add lower
    pop ebx
    ret

; get current date/time from RTC
get_datetime:
    pusha
    
    ; read seconds (register 0x00)
    mov al, 0x00
    call read_cmos
    call bcd_to_binary
    mov [rtc_second], al
    
    ; read minutes (register 0x02)
    mov al, 0x02
    call read_cmos
    call bcd_to_binary
    mov [rtc_minute], al
    
    ; read hours (register 0x04)
    mov al, 0x04
    call read_cmos
    call bcd_to_binary
    mov [rtc_hour], al
    
    ; read day (register 0x07)
    mov al, 0x07
    call read_cmos
    call bcd_to_binary
    mov [rtc_day], al
    
    ; read month (register 0x08)
    mov al, 0x08
    call read_cmos
    call bcd_to_binary
    mov [rtc_month], al
    
    ; read year (register 0x09)
    mov al, 0x09
    call read_cmos
    call bcd_to_binary
    mov [rtc_year], al
    
    popa
    ret

; print current date/time
print_datetime:
    pusha
    
    call get_datetime
    
    ; print month
    movzx eax, byte [rtc_month]
    call print_decimal
    mov al, '/'
    call print_char
    
    ; print day
    movzx eax, byte [rtc_day]
    call print_decimal
    mov al, '/'
    call print_char
    
    ; print year (20xx)
    mov esi, msg_year_prefix
    call print_string
    movzx eax, byte [rtc_year]
    call print_decimal
    
    ; space
    mov al, ' '
    call print_char
    
    ; print hour (with timezone offset)
    movzx eax, byte [rtc_hour]
    movsx ebx, byte [timezone_offset]
    add eax, ebx
    
    ; handle negative hours
    cmp eax, 0
    jge .hour_not_negative
    add eax, 24
    .hour_not_negative:
    
    ; handle hours >= 24
    cmp eax, 24
    jl .hour_ok
    sub eax, 24
    .hour_ok:
    
    call print_decimal
    mov al, ':'
    call print_char
    
    ; print minute
    movzx eax, byte [rtc_minute]
    cmp eax, 10
    jge .skip_zero_min
    mov al, '0'
    call print_char
    movzx eax, byte [rtc_minute]
    .skip_zero_min:
    call print_decimal
    mov al, ':'
    call print_char
    
    ; print second
    movzx eax, byte [rtc_second]
    cmp eax, 10
    jge .skip_zero_sec
    mov al, '0'
    call print_char
    movzx eax, byte [rtc_second]
    .skip_zero_sec:
    call print_decimal
    
    mov al, 10
    call print_char
    
    popa
    ret

; print decimal number
; EAX = number to print
print_decimal:
    pusha
    
    ; handle 0
    test eax, eax
    jnz .not_zero
    mov al, '0'
    call print_char
    popa
    ret
    
    .not_zero:
    mov ebx, 10
    xor ecx, ecx    ; digit counter
    
    ; convert to string (reversed)
    .convert_loop:
        xor edx, edx
        div ebx         ; EAX = EAX / 10, EDX = remainder
        add dl, '0'
        push edx
        inc ecx
        test eax, eax
        jnz .convert_loop
    
    ; print digits
    .print_loop:
        pop eax
        call print_char
        loop .print_loop
    
    popa
    ret

rtc_second: db 0
rtc_minute: db 0
rtc_hour:   db 0
rtc_day:    db 0
rtc_month:  db 0
rtc_year:   db 0
timezone_offset: db 0  ; offset in hours from UTC

; ========================================
; PCI BUS - FIND HARDWARE N SHIT
; ========================================

; read PCI config space
; EAX = bus/device/function/offset
; returns EAX = data
pci_read:
    push edx
    mov edx, 0xCF8      ; PCI config address port
    out dx, eax
    mov edx, 0xCFC      ; PCI config data port
    in eax, dx
    pop edx
    ret

; check if device exists at bus/device/function
; AL = bus, AH = device, BL = function
; returns EAX = vendor/device ID (0xFFFFFFFF if no device)
pci_check_device:
    push ebx
    push ecx
    
    ; build address: 0x80000000 | (bus << 16) | (device << 11) | (function << 8) | offset
    movzx ecx, al       ; bus
    shl ecx, 16
    movzx edx, ah       ; device
    shl edx, 11
    or ecx, edx
    movzx edx, bl       ; function
    shl edx, 8
    or ecx, edx
    or ecx, 0x80000000  ; enable bit
    
    mov eax, ecx
    call pci_read
    
    pop ecx
    pop ebx
    ret

; scan PCI bus and print all devices
scan_pci:
    pusha
    
    mov esi, msg_pci_scanning
    call print_string
    
    xor ebx, ebx        ; bus counter
    .bus_loop:
        xor ecx, ecx    ; device counter
        .device_loop:
            ; check device
            mov al, bl          ; bus
            mov ah, cl          ; device
            push ebx
            push ecx
            xor ebx, ebx        ; function 0
            call pci_check_device
            pop ecx
            pop ebx
            
            ; if vendor ID is 0xFFFF, device doesn't exist
            cmp ax, 0xFFFF
            je .next_device
            
            ; device found! print it
            push eax
            mov esi, msg_pci_found
            call print_string
            
            ; print bus
            movzx eax, bl
            call print_hex_byte
            mov al, ':'
            call print_char
            
            ; print device
            movzx eax, cl
            call print_hex_byte
            mov al, ' '
            call print_char
            
            ; print vendor:device ID
            pop eax
            push eax
            shr eax, 16
            call print_hex_word
            mov al, ':'
            call print_char
            pop eax
            and eax, 0xFFFF
            call print_hex_word
            mov al, 10
            call print_char
            
            .next_device:
                inc cl
                cmp cl, 32      ; 32 devices per bus
                jl .device_loop
        
        inc bl
        cmp bl, 8           ; scan 8 buses
        jl .bus_loop
    
    mov esi, msg_pci_done
    call print_string
    
    popa
    ret

; print byte as hex
; AL = byte
print_hex_byte:
    pusha
    mov bl, al
    shr al, 4
    call .print_nibble
    mov al, bl
    and al, 0x0F
    call .print_nibble
    popa
    ret
    .print_nibble:
        cmp al, 10
        jl .digit
        add al, 'A' - 10
        call print_char
        ret
        .digit:
            add al, '0'
            call print_char
            ret

; print word as hex
; AX = word
print_hex_word:
    pusha
    push eax
    shr eax, 8
    call print_hex_byte
    pop eax
    call print_hex_byte
    popa
    ret

msg_pci_scanning: db 'Scanning PCI bus...', 10, 0
msg_pci_found:    db '  ', 0
msg_pci_done:     db 'PCI scan complete.', 10, 0

; ========================================
; RTL8139 NETWORK DRIVER - GET ONLINE
; ========================================

; RTL8139 vendor/device ID
RTL8139_VENDOR_ID equ 0x10EC
RTL8139_DEVICE_ID equ 0x8139

; RTL8139 registers
RTL8139_IDR0      equ 0x00    ; MAC address
RTL8139_MAR0      equ 0x08    ; multicast
RTL8139_RBSTART   equ 0x30    ; RX buffer start
RTL8139_CMD       equ 0x37    ; command register
RTL8139_IMR       equ 0x3C    ; interrupt mask
RTL8139_ISR       equ 0x3E    ; interrupt status
RTL8139_TCR       equ 0x40    ; TX config
RTL8139_RCR       equ 0x44    ; RX config
RTL8139_CONFIG1   equ 0x52    ; config register

; commands
CMD_RESET         equ 0x10
CMD_RX_ENABLE     equ 0x08
CMD_TX_ENABLE     equ 0x04

rtl8139_found:    db 0
rtl8139_io_base:  dd 0
rtl8139_mac:      times 6 db 0
rtl8139_rx_buffer: dd 0

; Network stack buffers and variables
rtl8139_tx_buffer_data: times 2048 db 0
rtl8139_rx_buffer_data: times (8192 + 16) db 0
rtl8139_tx_current: dd 0
rtl8139_rx_ptr: dd 0

; find and initialize RTL8139
init_rtl8139:
    pusha
    
    mov esi, msg_rtl_scanning
    call print_string
    
    ; scan PCI bus for RTL8139
    xor ebx, ebx
    .bus_loop:
        xor ecx, ecx
        .device_loop:
            mov al, bl
            mov ah, cl
            push ebx
            push ecx
            xor ebx, ebx
            call pci_check_device
            pop ecx
            pop ebx
            
            cmp ax, 0xFFFF
            je .next_device
            
            ; check if it's RTL8139
            cmp ax, RTL8139_VENDOR_ID
            jne .next_device
            
            shr eax, 16
            cmp ax, RTL8139_DEVICE_ID
            jne .next_device
            
            ; found it!
            mov byte [rtl8139_found], 1
            
            ; get IO base address (BAR0)
            mov al, bl
            mov ah, cl
            push ebx
            push ecx
            movzx ebx, bl
            shl ebx, 16
            movzx edx, cl
            shl edx, 11
            or ebx, edx
            or ebx, 0x80000010  ; BAR0 at offset 0x10
            mov eax, ebx
            call pci_read
            and eax, 0xFFFFFFF0
            mov [rtl8139_io_base], eax
            pop ecx
            pop ebx
            
            mov esi, msg_rtl_found
            call print_string
            mov eax, [rtl8139_io_base]
            call print_hex
            mov al, 10
            call print_char
            
            ; initialize the card
            call rtl8139_init_card
            jmp .done
            
            .next_device:
                inc cl
                cmp cl, 32
                jl .device_loop
        
        inc bl
        cmp bl, 8
        jl .bus_loop
    
    ; not found
    cmp byte [rtl8139_found], 0
    jne .done
    mov esi, msg_rtl_not_found
    call print_string
    
    .done:
        popa
        ret

; initialize RTL8139 card
rtl8139_init_card:
    pusha
    
    mov edx, [rtl8139_io_base]
    
    ; power on
    add edx, RTL8139_CONFIG1
    mov al, 0x00
    out dx, al
    
    ; software reset
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_CMD
    mov al, CMD_RESET
    out dx, al
    
    ; wait for reset
    .wait_reset:
        in al, dx
        test al, CMD_RESET
        jnz .wait_reset
    
    ; allocate RX buffer (8KB + 16 bytes + 1500 bytes)
    mov ecx, 8192 + 16 + 1500
    call malloc
    mov [rtl8139_rx_buffer], eax
    
    ; set RX buffer address
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_RBSTART
    out dx, eax
    
    ; set IMR (interrupt mask) - enable all interrupts
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_IMR
    mov ax, 0xFFFF
    out dx, ax
    
    ; set RCR (RX config) - accept all packets
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_RCR
    mov eax, 0x0000000F
    out dx, eax
    
    ; set TCR (TX config)
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_TCR
    mov eax, 0x03000000
    out dx, eax
    
    ; enable RX and TX
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_CMD
    mov al, CMD_RX_ENABLE | CMD_TX_ENABLE
    out dx, al
    
    ; read MAC address
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_IDR0
    mov ecx, 6
    mov edi, rtl8139_mac
    .read_mac:
        in al, dx
        stosb
        inc edx
        loop .read_mac
    
    ; print MAC address
    mov esi, msg_rtl_mac
    call print_string
    mov ecx, 6
    mov esi, rtl8139_mac
    .print_mac:
        lodsb
        call print_hex_byte
        dec ecx
        jz .mac_done
        mov al, ':'
        call print_char
        jmp .print_mac
    .mac_done:
        mov al, 10
        call print_char
    
    mov esi, msg_rtl_ready
    call print_string
    
    popa
    ret

msg_rtl_scanning:   db 'Looking for RTL8139...', 10, 0
msg_rtl_found:      db 'RTL8139 found at IO: 0x', 0
msg_rtl_not_found:  db 'RTL8139 not found', 10, 0
msg_rtl_mac:        db 'MAC Address: ', 0
msg_rtl_ready:      db 'Network card ready!', 10, 0

; ========================================
; MEMORY ALLOCATOR - MALLOC/FREE
; ========================================
; Memory Layout (after kernel loads):
;   0x00000000 - 0x000003FF : Real mode IVT (1KB)
;   0x00000400 - 0x000004FF : BIOS Data Area (256 bytes)
;   0x00000500 - 0x00007BFF : Free conventional memory (~29KB)
;   0x00007C00 - 0x00007DFF : Boot sector (512 bytes)
;   0x00007E00 - 0x00007FFF : Boot scratch space (512 bytes)
;   0x00008000 - 0x0000FFFF : Free (~32KB)
;   0x00010000 - 0x0001FFFF : Kernel code/data (~64KB actual, 120 sectors max)
;   0x00020000 - 0x0008FFFF : Free (~448KB)
;   0x00090000 - 0x0009FFFF : Stack (grows down, 64KB)
;   0x000A0000 - 0x000BFFFF : VGA video memory (128KB)
;   0x000C0000 - 0x000FFFFF : BIOS ROM area (256KB)
;   0x00100000 - 0x001FFFFF : Heap (1MB) ← malloc/free uses this
;   0x00200000+             : Extended memory (for future expansion)

; heap starts at 1MB (after kernel and stack)
HEAP_START equ 0x100000
HEAP_SIZE equ 0x100000      ; 1MB heap

; block header structure (16 bytes):
; offset 0: size (4 bytes)
; offset 4: is_free flag (4 bytes) - 1 if free, 0 if allocated
; offset 8: next block pointer (4 bytes)
; offset 12: magic number (4 bytes) - 0xDEADBEEF
BLOCK_HEADER_SIZE equ 16
HEAP_MAGIC equ 0xDEADBEEF

; page management for hot/cold memory
PAGE_SIZE equ 4096
PAGE_COUNT equ 256          ; track 256 pages (1MB / 4KB)
PAGE_HOT_THRESHOLD equ 10   ; accesses before page is "hot"
PAGE_COLD_THRESHOLD equ 2   ; ticks without access = "cold"

; page states
PAGE_FREE equ 0
PAGE_ALLOCATED equ 1
PAGE_HOT equ 2
PAGE_COLD equ 3
PAGE_COMPRESSED equ 4
PAGE_SWAPPED equ 5

heap_initialized: dd 0
heap_first_block: dd HEAP_START

; page tracking table (16 bytes per page)
; offset 0: state (1 byte)
; offset 1: access_count (1 byte)
; offset 2: ticks_since_access (2 bytes)
; offset 4: physical_addr (4 bytes)
; offset 8: compressed_size (4 bytes)
; offset 12: flags (4 bytes)
page_table: times (PAGE_COUNT * 16) db 0
page_stats_hot: dd 0
page_stats_cold: dd 0
page_stats_compressed: dd 0
page_stats_swapped: dd 0

; memory pressure management
memory_pressure: dd 0           ; 0=low, 1=medium, 2=high
free_page_count: dd PAGE_COUNT
compress_on_cold: db 1          ; auto-compress when page becomes cold

; swap space management
SWAP_START_SECTOR equ 100       ; start sector for swap space on disk
SWAP_SECTORS equ 256            ; 256 sectors = 128KB swap space
swap_bitmap: times 32 db 0      ; 256 bits for 256 swap slots
swap_write_count: dd 0          ; stats
swap_read_count: dd 0

; initialize the heap
init_heap:
    pusha
    
    ; check if already initialized
    cmp dword [heap_initialized], 1
    je .done
    
    ; set up the first free block
    mov edi, HEAP_START
    mov dword [edi], HEAP_SIZE - BLOCK_HEADER_SIZE  ; size
    mov dword [edi + 4], 1                          ; is_free = true
    mov dword [edi + 8], 0                          ; next = NULL
    mov dword [edi + 12], HEAP_MAGIC                ; magic
    
    mov dword [heap_initialized], 1
    
    .done:
        popa
        ret

; malloc - allocate memory
; ECX = size in bytes
; returns EAX = pointer to allocated memory (or 0 if failed)
malloc:
    push ebx
    push edx
    push esi
    push edi
    
    ; validate input
    test ecx, ecx
    jz .invalid_size
    
    ; check for overflow (max allocation 256KB)
    cmp ecx, 0x40000
    ja .invalid_size
    
    ; make sure heap is initialized
    call init_heap
    
    ; align size to 16 bytes for better cache performance
    add ecx, 15
    and ecx, 0xFFFFFFF0
    
    ; find a free block that fits (first-fit algorithm)
    mov esi, HEAP_START
    
    .find_loop:
        ; bounds check - make sure we're still in heap
        mov eax, esi
        sub eax, HEAP_START
        cmp eax, HEAP_SIZE
        jae .not_found
        
        ; check if this is a valid block
        cmp dword [esi + 12], HEAP_MAGIC
        jne .not_found
        
        ; is it free?
        cmp dword [esi + 4], 1
        jne .next_block
        
        ; is it big enough?
        mov eax, [esi]      ; block size
        cmp eax, ecx
        jl .next_block
        
        ; found a good block! allocate it
        mov dword [esi + 4], 0  ; mark as allocated
        
        ; TODO: split block if it's much larger than needed
        ; (optimization for later)
        
        ; return pointer (skip header)
        lea eax, [esi + BLOCK_HEADER_SIZE]
        jmp .done
        
        .next_block:
            mov esi, [esi + 8]  ; next block
            test esi, esi
            jnz .find_loop
    
    .not_found:
    .invalid_size:
        xor eax, eax        ; return NULL
    
    .done:
        pop edi
        pop esi
        pop edx
        pop ebx
        ret

; free - deallocate memory
; EAX = pointer to memory
free:
    push ebx
    push esi
    push edi
    
    ; validate pointer is not NULL
    test eax, eax
    jz .invalid
    
    ; validate pointer is within heap bounds
    cmp eax, HEAP_START + BLOCK_HEADER_SIZE
    jb .invalid
    mov ebx, HEAP_START + HEAP_SIZE
    cmp eax, ebx
    jae .invalid
    
    ; get block header (pointer - 16)
    sub eax, BLOCK_HEADER_SIZE
    mov esi, eax
    
    ; verify magic number
    cmp dword [esi + 12], HEAP_MAGIC
    jne .invalid
    
    ; check if already free (double-free protection)
    cmp dword [esi + 4], 1
    je .invalid
    
    ; mark as free
    mov dword [esi + 4], 1
    
    ; TODO: coalesce adjacent free blocks
    ; (optimization for later to reduce fragmentation)
    
    .invalid:
        pop edi
        pop esi
        pop ebx
        ret

; ========================================
; PAGE MANAGEMENT - HOT/COLD MEMORY
; ========================================
; Advanced memory management with page tracking, compression, and swapping
; Pages can be: FREE, ALLOCATED, HOT (frequently accessed), COLD (rarely used),
; COMPRESSED (RLE compressed in memory), or SWAPPED (saved to disk)

; initialize page management system
init_page_mgmt:
    pusha
    
    ; mark all pages as free initially
    mov ecx, PAGE_COUNT
    mov edi, page_table
    xor eax, eax
    .init_loop:
        stosb               ; state = FREE
        stosb               ; access_count = 0
        stosw               ; ticks_since_access = 0
        stosd               ; physical_addr = 0
        stosd               ; compressed_size = 0
        stosd               ; flags = 0
        loop .init_loop
    
    popa
    ret

; allocate a page (4KB)
; returns EAX = page index (or -1 if failed)
alloc_page:
    push ebx
    push ecx
    push edi
    
    ; find first free page
    mov ecx, PAGE_COUNT
    mov edi, page_table
    xor ebx, ebx
    
    .search_loop:
        cmp byte [edi], PAGE_FREE
        je .found_page
        add edi, 16
        inc ebx
        loop .search_loop
    
    ; no free pages
    mov eax, -1
    jmp .done
    
    .found_page:
        ; mark as allocated
        mov byte [edi], PAGE_ALLOCATED
        mov byte [edi + 1], 0           ; access_count = 0
        mov word [edi + 2], 0           ; ticks_since_access = 0
        
        ; calculate physical address
        mov eax, ebx
        shl eax, 12                     ; * 4096
        add eax, HEAP_START
        mov [edi + 4], eax              ; store physical addr
        
        ; update free count
        dec dword [free_page_count]
        
        mov eax, ebx                    ; return page index
    
    .done:
        pop edi
        pop ecx
        pop ebx
        ret

; free a page
; EAX = page index
free_page:
    push ebx
    push edi
    
    ; bounds check
    cmp eax, PAGE_COUNT
    jge .done
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4                          ; * 16
    add ebx, page_table
    
    ; check if compressed/swapped, need to free that too
    cmp byte [ebx], PAGE_COMPRESSED
    je .free_compressed
    cmp byte [ebx], PAGE_SWAPPED
    je .free_swapped
    jmp .mark_free
    
    .free_compressed:
        dec dword [page_stats_compressed]
        jmp .mark_free
    
    .free_swapped:
        dec dword [page_stats_swapped]
        jmp .mark_free
    
    .mark_free:
        mov byte [ebx], PAGE_FREE
        mov dword [ebx + 4], 0
        mov dword [ebx + 8], 0
        
        ; update free count
        inc dword [free_page_count]
    
    .done:
        pop edi
        pop ebx
        ret

; access a page (track for hot/cold)
; EAX = page index
access_page:
    push ebx
    push edi
    
    ; bounds check
    cmp eax, PAGE_COUNT
    jge .done
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4
    add ebx, page_table
    
    ; check if page is swapped out - need to swap in first
    cmp byte [ebx], PAGE_SWAPPED
    jne .not_swapped
    
    push eax
    call swap_page_in
    pop eax
    
    .not_swapped:
    ; increment access count
    inc byte [ebx + 1]
    mov word [ebx + 2], 0               ; reset ticks_since_access
    
    ; check if should promote to hot
    cmp byte [ebx + 1], PAGE_HOT_THRESHOLD
    jl .done
    
    ; promote to hot if not already
    cmp byte [ebx], PAGE_HOT
    je .done
    
    mov byte [ebx], PAGE_HOT
    inc dword [page_stats_hot]
    
    .done:
        pop edi
        pop ebx
        ret

; update page aging (call from timer)
update_page_aging:
    pusha
    
    mov ecx, PAGE_COUNT
    mov edi, page_table
    
    .age_loop:
        ; skip free pages
        cmp byte [edi], PAGE_FREE
        je .next_page
        
        ; increment ticks since access
        inc word [edi + 2]
        
        ; check if should demote to cold
        cmp word [edi + 2], PAGE_COLD_THRESHOLD
        jl .next_page
        
        ; demote hot page to cold
        cmp byte [edi], PAGE_HOT
        jne .check_allocated
        
        mov byte [edi], PAGE_COLD
        dec dword [page_stats_hot]
        inc dword [page_stats_cold]
        
        ; auto-compress if enabled
        cmp byte [compress_on_cold], 1
        jne .next_page
        
        push eax
        push edi
        ; calculate page index
        mov eax, edi
        sub eax, page_table
        shr eax, 4
        call compress_page
        pop edi
        pop eax
        jmp .next_page
        
        .check_allocated:
            ; demote allocated to cold
            cmp byte [edi], PAGE_ALLOCATED
            jne .next_page
            
            mov byte [edi], PAGE_COLD
            inc dword [page_stats_cold]
            
            ; auto-compress if enabled
            cmp byte [compress_on_cold], 1
            jne .next_page
            
            push eax
            push edi
            ; calculate page index
            mov eax, edi
            sub eax, page_table
            shr eax, 4
            call compress_page
            pop edi
            pop eax
        
        .next_page:
            add edi, 16
            loop .age_loop
    
    ; calculate memory pressure
    call calculate_memory_pressure
    
    popa
    ret

; calculate current memory pressure
calculate_memory_pressure:
    pusha
    
    ; count free pages
    xor ebx, ebx        ; free count
    mov ecx, PAGE_COUNT
    mov edi, page_table
    
    .count_loop:
        cmp byte [edi], PAGE_FREE
        jne .not_free
        inc ebx
        .not_free:
        add edi, 16
        loop .count_loop
    
    mov [free_page_count], ebx
    
    ; calculate pressure level
    ; high pressure: < 10% free (< 25 pages)
    ; medium pressure: < 25% free (< 64 pages)
    ; low pressure: >= 25% free
    
    cmp ebx, 25
    jl .high_pressure
    cmp ebx, 64
    jl .medium_pressure
    
    ; low pressure
    mov dword [memory_pressure], 0
    jmp .done
    
    .medium_pressure:
        mov dword [memory_pressure], 1
        ; compress some cold pages proactively
        call compress_cold_pages
        jmp .done
    
    .high_pressure:
        mov dword [memory_pressure], 2
        ; aggressively compress cold pages
        call compress_cold_pages
        ; swap out compressed pages if still high pressure
        call swap_out_pages
        ; swap out compressed pages if still high pressure
        call swap_out_pages
    
    .done:
        popa
        ret

; disk I/O functions
; write sector to disk
; eax = LBA sector number
; edi = source buffer
write_disk_sector:
    pusha
    
    push eax
    
    ; wait for disk ready
    mov dx, 0x1F7
    .wait_ready:
        in al, dx
        test al, 0x80
        jnz .wait_ready
    
    pop eax
    
    ; send sector count (1)
    mov dx, 0x1F2
    mov al, 1
    out dx, al
    
    ; send LBA
    pop eax
    push eax
    mov dx, 0x1F3
    out dx, al
    
    shr eax, 8
    mov dx, 0x1F4
    out dx, al
    
    shr eax, 8
    mov dx, 0x1F5
    out dx, al
    
    shr eax, 8
    mov dx, 0x1F6
    and al, 0x0F
    or al, 0xE0         ; LBA mode, master
    out dx, al
    
    ; send write command
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al
    
    ; wait for ready
    .wait_write:
        in al, dx
        test al, 0x80
        jnz .wait_write
    
    ; write 256 words (512 bytes)
    mov ecx, 256
    mov dx, 0x1F0
    .write_loop:
        mov ax, [edi]
        out dx, ax
        add edi, 2
        loop .write_loop
    
    pop eax
    popa
    ret

; read sector from disk
; eax = LBA sector number
; edi = dest buffer
read_disk_sector:
    pusha
    
    push eax
    
    ; wait for disk ready
    mov dx, 0x1F7
    .wait_ready:
        in al, dx
        test al, 0x80
        jnz .wait_ready
    
    pop eax
    
    ; send sector count (1)
    mov dx, 0x1F2
    mov al, 1
    out dx, al
    
    ; send LBA
    pop eax
    push eax
    mov dx, 0x1F3
    out dx, al
    
    shr eax, 8
    mov dx, 0x1F4
    out dx, al
    
    shr eax, 8
    mov dx, 0x1F5
    out dx, al
    
    shr eax, 8
    mov dx, 0x1F6
    and al, 0x0F
    or al, 0xE0         ; LBA mode, master
    out dx, al
    
    ; send read command
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al
    
    ; wait for ready
    .wait_read:
        in al, dx
        test al, 0x80
        jnz .wait_read
    
    ; read 256 words (512 bytes)
    mov ecx, 256
    mov dx, 0x1F0
    .read_loop:
        in ax, dx
        mov [edi], ax
        add edi, 2
        loop .read_loop
    
    pop eax
    popa
    ret

; allocate a swap slot
; returns: eax = swap slot number, or -1 if full
alloc_swap_slot:
    push ebx
    push ecx
    push edx
    
    xor ebx, ebx        ; byte index
    .byte_loop:
        cmp ebx, 32
        jge .no_slot
        
        mov al, [swap_bitmap + ebx]
        cmp al, 0xFF
        je .next_byte
        
        ; find free bit in this byte
        xor ecx, ecx
        .bit_loop:
            cmp ecx, 8
            jge .next_byte
            
            mov dl, 1
            shl dl, cl
            test al, dl
            jz .found_slot
            
            inc ecx
            jmp .bit_loop
        
        .next_byte:
            inc ebx
            jmp .byte_loop
    
    .found_slot:
        ; mark bit as used
        or byte [swap_bitmap + ebx], dl
        
        ; calculate slot number
        mov eax, ebx
        shl eax, 3
        add eax, ecx
        jmp .done
    
    .no_slot:
        mov eax, -1
    
    .done:
        pop edx
        pop ecx
        pop ebx
        ret

; free a swap slot
; eax = swap slot number
free_swap_slot:
    push ebx
    push ecx
    push edx
    
    ; calculate byte and bit
    mov ebx, eax
    shr ebx, 3          ; byte index
    mov ecx, eax
    and ecx, 7          ; bit index
    
    ; clear bit
    mov dl, 1
    shl dl, cl
    not dl
    and byte [swap_bitmap + ebx], dl
    
    pop edx
    pop ecx
    pop ebx
    ret

; swap page out to disk
; eax = page index
swap_page_out:
    pusha
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4
    add ebx, page_table
    
    ; check if page can be swapped
    movzx ecx, byte [ebx]
    cmp ecx, PAGE_COLD
    je .can_swap
    cmp ecx, PAGE_COMPRESSED
    je .can_swap
    jmp .done           ; can't swap hot or allocated pages
    
    .can_swap:
        ; allocate swap slot
        call alloc_swap_slot
        cmp eax, -1
        je .done        ; no swap space available
        
        mov edx, eax    ; save swap slot
        
        ; calculate disk sector (8 sectors per 4KB page)
        mov eax, edx
        shl eax, 3      ; * 8 sectors
        add eax, SWAP_START_SECTOR
        
        ; get physical address
        mov edi, [ebx + 4]
        
        ; write 8 sectors (4KB)
        mov ecx, 8
        .write_sectors:
            push eax
            push ecx
            call write_disk_sector
            pop ecx
            pop eax
            inc eax
            add edi, 512
            loop .write_sectors
        
        ; update page state
        mov byte [ebx], PAGE_SWAPPED
        mov dword [ebx + 8], edx    ; store swap slot in compressed_size field
        
        ; update stats
        dec dword [page_stats_cold]
        inc dword [page_stats_swapped]
        inc dword [swap_write_count]
        inc dword [free_page_count]
    
    .done:
        popa
        ret

; swap page in from disk
; eax = page index
swap_page_in:
    pusha
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4
    add ebx, page_table
    
    ; check if page is swapped
    cmp byte [ebx], PAGE_SWAPPED
    jne .done
    
    ; get swap slot
    mov edx, [ebx + 8]
    
    ; calculate disk sector
    mov eax, edx
    shl eax, 3
    add eax, SWAP_START_SECTOR
    
    ; get physical address
    mov edi, [ebx + 4]
    
    ; read 8 sectors (4KB)
    mov ecx, 8
    .read_sectors:
        push eax
        push ecx
        call read_disk_sector
        pop ecx
        pop eax
        inc eax
        add edi, 512
        loop .read_sectors
    
    ; free swap slot
    mov eax, edx
    call free_swap_slot
    
    ; update page state
    mov byte [ebx], PAGE_COLD
    mov dword [ebx + 8], 0
    
    ; update stats
    dec dword [page_stats_swapped]
    inc dword [page_stats_cold]
    inc dword [swap_read_count]
    dec dword [free_page_count]
    
    .done:
        popa
        ret

; ========================================
; MODULAR INCLUDES - EXTERNAL SUBSYSTEMS
; ========================================
%include "swap_system.asm"    ; Swap/compression for memory management
%include "network.asm"        ; Basic network stack (ARP, ICMP)
%include "graphics.asm"       ; VGA graphics modes
%include "gui.asm"            ; Basic GUI widgets
%include "j3kfs.asm"          ; file system (stores your garbage)
%include "sound.asm"          ; annoying beep noises
%include "vmm.asm"            ; virtual memory magic (don't touch it)
%include "editor.asm"         ; the goddamn text editor

; Advanced networking disabled because I'm lazy

; compress multiple cold pages (for memory pressure)
compress_cold_pages:
    pusha
    
    mov ecx, PAGE_COUNT
    mov edi, page_table
    mov ebx, 0          ; compressed count
    
    .compress_loop:
        cmp byte [edi], PAGE_COLD
        jne .next_page
        
        ; try to compress this page
        push eax
        push edi
        mov eax, edi
        sub eax, page_table
        shr eax, 4
        call compress_page
        pop edi
        pop eax
        
        ; limit compression per call
        inc ebx
        cmp ebx, 10         ; compress max 10 pages per call
        jge .done
        
        .next_page:
            add edi, 16
            loop .compress_loop
    
    .done:
        popa
        ret

; compress a cold page (simple RLE compression)
; EAX = page index
; returns EAX = compressed size (or 0 if failed)
compress_page:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    
    ; get page entry
    mov ebx, eax
    shl ebx, 4
    add ebx, page_table
    
    ; must be cold to compress
    cmp byte [ebx], PAGE_COLD
    jne .failed
    
    ; source = physical address
    mov esi, [ebx + 4]
    
    ; allocate temp buffer for compressed data (max 4KB)
    mov ecx, PAGE_SIZE
    call malloc
    test eax, eax
    jz .failed
    mov edi, eax
    
    ; simple RLE compression
    mov ecx, PAGE_SIZE
    xor edx, edx                        ; compressed size counter
    
    .compress_loop:
        test ecx, ecx
        jz .compress_done
        
        lodsb                           ; read byte
        mov bl, al
        mov bh, 1                       ; run length
        
        ; count consecutive bytes
        .count_run:
            dec ecx
            test ecx, ecx
            jz .write_run
            
            cmp byte [esi], bl
            jne .write_run
            
            inc bh
            inc esi
            cmp bh, 255
            jl .count_run
        
        .write_run:
            mov byte [edi], bl          ; write byte value
            inc edi
            mov byte [edi], bh          ; write run length
            inc edi
            add edx, 2
            
            jmp .compress_loop
    
    .compress_done:
        ; update page entry
        mov eax, ebx
        sub eax, page_table
        shr eax, 4
        
        mov byte [ebx], PAGE_COMPRESSED
        mov [ebx + 8], edx              ; compressed_size
        inc dword [page_stats_compressed]
        dec dword [page_stats_cold]
        
        mov eax, edx                    ; return compressed size
        jmp .done
    
    .failed:
        xor eax, eax
    
    .done:
        pop edi
        pop esi
        pop edx
        pop ecx
        pop ebx
        ret

; get page statistics
; returns formatted string with page stats
get_page_stats:
    pusha
    
    mov esi, msg_page_stats
    call print_string
    
    ; memory pressure
    mov esi, msg_mem_pressure
    call print_string
    mov eax, [memory_pressure]
    cmp eax, 0
    je .low_pressure
    cmp eax, 1
    je .med_pressure
    mov esi, msg_pressure_high
    jmp .print_pressure
    .med_pressure:
        mov esi, msg_pressure_medium
        jmp .print_pressure
    .low_pressure:
        mov esi, msg_pressure_low
    .print_pressure:
        call print_string
    
    ; free pages
    mov esi, msg_free_pages
    call print_string
    mov eax, [free_page_count]
    call print_decimal
    mov al, '/'
    call print_char
    mov eax, PAGE_COUNT
    call print_decimal
    mov al, 10
    call print_char
    
    ; hot pages
    mov esi, msg_page_hot
    call print_string
    mov eax, [page_stats_hot]
    call print_decimal
    mov al, 10
    call print_char
    
    ; cold pages
    mov esi, msg_page_cold
    call print_string
    mov eax, [page_stats_cold]
    call print_decimal
    mov al, 10
    call print_char
    
    ; compressed pages
    mov esi, msg_page_compressed
    call print_string
    mov eax, [page_stats_compressed]
    call print_decimal
    mov al, 10
    call print_char
    
    ; swapped pages
    mov esi, msg_page_swapped
    call print_string
    mov eax, [page_stats_swapped]
    call print_decimal
    mov al, 10
    call print_char
    
    ; swap activity
    mov esi, msg_swap_writes
    call print_string
    mov eax, [swap_write_count]
    call print_decimal
    mov al, 10
    call print_char
    
    mov esi, msg_swap_reads
    call print_string
    mov eax, [swap_read_count]
    call print_decimal
    mov al, 10
    call print_char
    
    popa
    ret

msg_page_stats:      db 'Page Statistics:', 10, 0
msg_mem_pressure:    db '  Memory pressure: ', 0
msg_pressure_low:    db 'LOW', 10, 0
msg_pressure_medium: db 'MEDIUM (compressing)', 10, 0
msg_pressure_high:   db 'HIGH (aggressive compression!)', 10, 0
msg_free_pages:      db '  Free pages: ', 0
msg_page_hot:        db '  Hot pages: ', 0
msg_page_cold:       db '  Cold pages: ', 0
msg_page_compressed: db '  Compressed pages: ', 0
msg_page_swapped:    db '  Swapped pages: ', 0
msg_swap_writes:     db '  Swap writes: ', 0
msg_swap_reads:      db '  Swap reads: ', 0
msg_swap_info:       db 'Swap Space Information:', 10, 0
msg_swap_used:       db '  Used: ', 0
msg_swap_slots:      db ' slots', 10, 0
msg_swap_kb:         db '  Size: ', 0
msg_kb_used:         db ' KB in use', 10, 0

; ========================================
; SYSTEM CALLS - INT 0x80 INTERFACE
; ========================================

; syscall numbers
SYSCALL_EXIT    equ 0
SYSCALL_PRINT   equ 1
SYSCALL_READ    equ 2
SYSCALL_MALLOC  equ 3
SYSCALL_FREE    equ 4

syscall_handler:
    ; save all registers
    pusha
    push ds
    push es
    
    ; set up kernel segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    
    ; EAX = syscall number
    ; EBX, ECX, EDX = arguments
    
    cmp eax, SYSCALL_EXIT
    je .syscall_exit
    cmp eax, SYSCALL_PRINT
    je .syscall_print
    cmp eax, SYSCALL_READ
    je .syscall_read
    cmp eax, SYSCALL_MALLOC
    je .syscall_malloc
    cmp eax, SYSCALL_FREE
    je .syscall_free
    
    ; unknown syscall
    mov eax, -1
    jmp .done
    
    .syscall_exit:
        ; just halt for now
        cli
        hlt
    
    .syscall_print:
        ; EBX = string pointer
        mov esi, ebx
        call print_string
        xor eax, eax
        jmp .done
    
    .syscall_read:
        ; EBX = buffer, ECX = max length
        call getchar_wait
        mov byte [ebx], al
        mov eax, 1      ; return 1 byte read
        jmp .done
    
    .syscall_malloc:
        ; ECX = size
        call malloc
        ; EAX already contains the result
        jmp .done
    
    .syscall_free:
        ; EBX = pointer
        mov eax, ebx
        call free
        xor eax, eax
        jmp .done
    
    .done:
        ; restore registers
        mov [.syscall_return], eax
        pop es
        pop ds
        popa
        mov eax, [.syscall_return]
        iret
    
    .syscall_return: dd 0

; ========================================
; TASK SWITCHING - MULTITASKING N SHIT
; ========================================

; TSS structure (104 bytes)
align 16
tss:
    dd 0            ; previous task link
    dd 0x90000      ; ESP0 (kernel stack)
    dd 0x10         ; SS0 (kernel data segment)
    times 23 dd 0   ; rest of TSS fields
    dw 0            ; reserved
    dw 104          ; IO map base (no IO map)

; task control block
MAX_TASKS equ 8
TASK_RUNNING equ 1
TASK_READY equ 2
TASK_BLOCKED equ 3

task_count: dd 0
current_task: dd 0

align 16
task_table: times (MAX_TASKS * 64) db 0  ; 8 tasks, 64 bytes each
; each task: ESP, EBP, EBX, ESI, EDI, EIP, state, etc

; initialize TSS
init_tss:
    pusha
    
    ; update GDT with TSS address (segment 0x28 = 5th descriptor)
    mov eax, tss
    mov edi, 0x1000 + (5 * 8)  ; GDT is at loader location
    mov [edi + 2], ax          ; base low
    shr eax, 16
    mov [edi + 4], al          ; base mid
    mov [edi + 7], ah          ; base high
    
    ; load TSS
    mov ax, 0x28               ; TSS selector
    ltr ax
    
    popa
    ret

; create a new task
; ESI = task entry point
; returns EAX = task ID (or -1 if failed)
create_task:
    push ebx
    push ecx
    push edi
    
    ; check if we have space
    mov eax, [task_count]
    cmp eax, MAX_TASKS
    jge .no_space
    
    ; get task slot
    mov ebx, eax
    imul ebx, 64
    add ebx, task_table
    
    ; allocate stack (4KB per task)
    mov ecx, 4096
    call malloc
    test eax, eax
    jz .no_space
    
    ; set up task structure
    add eax, 4096              ; stack grows down
    mov [ebx], eax             ; ESP
    mov [ebx + 4], eax         ; EBP
    mov [ebx + 20], esi        ; EIP (entry point)
    mov dword [ebx + 24], TASK_READY  ; state
    
    ; increment task count
    inc dword [task_count]
    
    ; return task ID
    mov eax, [task_count]
    dec eax
    jmp .done
    
    .no_space:
        mov eax, -1
    
    .done:
        pop edi
        pop ecx
        pop ebx
        ret

; switch to next task (called by timer)
switch_task:
    pusha
    
    ; check if we have multiple tasks
    cmp dword [task_count], 2
    jl .done
    
    ; save current task state
    mov eax, [current_task]
    imul eax, 64
    add eax, task_table
    
    mov [eax], esp             ; save ESP
    mov [eax + 4], ebp         ; save EBP
    mov [eax + 8], ebx
    mov [eax + 12], esi
    mov [eax + 16], edi
    
    ; find next ready task
    mov ebx, [current_task]
    .find_next:
        inc ebx
        cmp ebx, [task_count]
        jl .check_task
        xor ebx, ebx           ; wrap around
        
    .check_task:
        mov eax, ebx
        imul eax, 64
        add eax, task_table
        cmp dword [eax + 24], TASK_READY
        je .switch_to_task
        
        cmp ebx, [current_task]
        jne .find_next
        jmp .done              ; no other ready tasks
    
    .switch_to_task:
        mov [current_task], ebx
        
        ; restore task state
        mov esp, [eax]
        mov ebp, [eax + 4]
        mov ebx, [eax + 8]
        mov esi, [eax + 12]
        mov edi, [eax + 16]
    
    .done:
        popa
        ret

irq0_handler:
    pusha
    
    ; count up
    inc dword [timer_ticks]
    
    ; Update VMM page aging every 10 ticks
    mov eax, [timer_ticks]
    xor edx, edx
    mov ebx, 10
    div ebx
    test edx, edx
    jnz .no_vmm_aging
    call vmm_page_timer_tick
    .no_vmm_aging:
    
    ; update page aging every 100 ticks
    mov eax, [timer_ticks]
    xor edx, edx
    mov ebx, 100
    div ebx
    test edx, edx
    jnz .no_page_aging
    call update_page_aging
    .no_page_aging:
    
    ; do task switching every 10 ticks
    mov eax, [timer_ticks]
    and eax, 0x0F
    test eax, eax
    jnz .no_switch
    
    call switch_task
    
    .no_switch:
    
    ; tell PIC we're done
    mov al, 0x20
    out 0x20, al
    
    popa
    iret

; ========================================
; KEYBOARD - SCAN CODES N SHIT
; ========================================
KEY_BUFFER_SIZE equ 256

key_buffer: times KEY_BUFFER_SIZE db 0
key_read_pos: dd 0
key_write_pos: dd 0
shift_pressed: db 0
caps_lock: db 0
extended_mode: db 0

; scancode to ascii table (US QWERTY lowercase)
scancode_to_ascii:
    db 0,27,'1','2','3','4','5','6','7','8','9','0','-','=',8,9
    db 'q','w','e','r','t','y','u','i','o','p','[',']',13,0,'a','s'
    db 'd','f','g','h','j','k','l',';',39,'`',0,'\','z','x','c','v'
    db 'b','n','m',',','.','/',0,'*',0,' ',0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  ; F-keys etc
    db 0,0,0,0,0,0,0,0                ; more keys
    ; extended scancodes (0xE0 prefix)
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,1,0,0,2,0,3,0,4  ; arrows: 0x48=up(1), 0x4B=left(2), 0x4D=right(3), 0x50=down(4)

; scancode to ascii table with shift
scancode_to_ascii_shift:
    db 0,27,'!','@','#','$','%','^','&','*','(',')','_','+',8,9
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}',13,0,'A','S'
    db 'D','F','G','H','J','K','L',':',34,'~',0,'|','Z','X','C','V'
    db 'B','N','M','<','>','?',0,'*',0,' ',0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,1,0,0,2,0,3,0,4

init_keyboard:
    ; BIOS already did the work
    ret

irq1_handler:
    pusha
    
    ; grab the scancode
    in al, 0x60
    
    ; check for extended scancode prefix (0xE0)
    cmp al, 0xE0
    je .extended_prefix
    
    ; check if we're in extended mode
    cmp byte [extended_mode], 1
    je .handle_extended
    
    ; check for shift keys
    cmp al, 0x2A        ; left shift press
    je .left_shift_press
    cmp al, 0xAA        ; left shift release
    je .left_shift_release
    cmp al, 0x36        ; right shift press
    je .right_shift_press
    cmp al, 0xB6        ; right shift release
    je .right_shift_release
    
    ; check for caps lock
    cmp al, 0x3A
    je .caps_lock_toggle
    
    ; check if key release (bit 7 set)
    test al, 0x80
    jnz .done
    
    jmp .convert_scancode
    
    .extended_prefix:
        mov byte [extended_mode], 1
        jmp .done
    
    .handle_extended:
        mov byte [extended_mode], 0
        test al, 0x80
        jnz .done
        
        ; handle arrow keys
        cmp al, 0x48        ; up arrow
        je .arrow_up
        cmp al, 0x50        ; down arrow
        je .arrow_down
        jmp .done
        
        .arrow_up:
            mov al, 1       ; special code for up
            jmp .got_char
        .arrow_down:
            mov al, 4       ; special code for down
            jmp .got_char
    
    .convert_scancode:
    ; convert scancode to ASCII
    movzx ebx, al
    cmp ebx, 58
    jge .done
    
    ; check if shift is pressed
    mov al, [shift_pressed]
    test al, al
    jnz .use_shift_table
    
    ; check caps lock for letters
    mov al, [caps_lock]
    test al, al
    jz .use_normal_table
    
    ; caps lock on - check if it's a letter (scancodes 16-25, 30-38, 44-50)
    cmp ebx, 16
    jl .use_normal_table
    cmp ebx, 50
    jg .use_normal_table
    
    ; it's a letter, use uppercase
    mov al, [scancode_to_ascii_shift + ebx]
    jmp .got_char
    
    .use_shift_table:
        mov al, [scancode_to_ascii_shift + ebx]
        jmp .got_char
    
    .use_normal_table:
        mov al, [scancode_to_ascii + ebx]
    
    .got_char:
        test al, al
        jz .done
        
        ; throw it in the buffer
        mov ebx, [key_write_pos]
        mov [key_buffer + ebx], al
        inc ebx
        and ebx, KEY_BUFFER_SIZE - 1
        mov [key_write_pos], ebx
        jmp .done
    
    .left_shift_press:
    .right_shift_press:
        mov byte [shift_pressed], 1
        jmp .done
    
    .left_shift_release:
    .right_shift_release:
        mov byte [shift_pressed], 0
        jmp .done
    
    .caps_lock_toggle:
        xor byte [caps_lock], 1
        jmp .done
    
    .done:
        ; tell PIC we're done
        mov al, 0x20
        out 0x20, al
        
        popa
        iret

; IRQ11 handler (network card)
irq11_handler:
    pusha
    
    ; Check if it's RTL8139
    mov edx, [rtl8139_io_base]
    test edx, edx
    jz .not_rtl8139
    
    ; Check interrupt status
    add edx, 0x3E           ; ISR register
    in ax, dx
    test ax, 0x01           ; RX OK
    jz .not_rx
    
    ; Handle received packet
    call rtl8139_handle_rx
    
    ; Clear interrupt
    mov edx, [rtl8139_io_base]
    add edx, 0x3E
    mov ax, 0x01
    out dx, ax
    
    .not_rx:
    .not_rtl8139:
    
    ; tell both PICs we're done (IRQ11 is on slave PIC)
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    
    popa
    iret

; IRQ12 handler (PS/2 mouse)
irq12_handler:
    pusha
    
    ; update mouse state
    call mouse_update
    
    ; tell both PICs we're done (IRQ12 is on slave PIC)
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    
    popa
    iret
    out 0xA0, al            ; Slave PIC
    out 0x20, al            ; Master PIC
    
    popa
    iret

getchar:
    ; returns character in AL or 0 if nothing there
    push ebx
    mov eax, [key_read_pos]
    mov ebx, [key_write_pos]
    cmp eax, ebx
    je .empty
    
    ; grab the char
    movzx eax, byte [key_buffer + eax]
    
    ; move read position
    mov ebx, [key_read_pos]
    inc ebx
    and ebx, KEY_BUFFER_SIZE - 1
    mov [key_read_pos], ebx
    
    pop ebx
    ret
    
    .empty:
        xor eax, eax
        pop ebx
        ret

getchar_wait:
    ; wait for a fucking key press
    .wait:
        call getchar
        test al, al
        jz .wait
        ret

; ========================================
; SHELL - COMMAND LINE SHIT
; ========================================
CMD_BUFFER_SIZE equ 128
HISTORY_SIZE equ 10

cmd_buffer: times CMD_BUFFER_SIZE db 0
cmd_length: dd 0
cmd_position: dd 0      ; cursor position in buffer

; command history
history_buffer: times (HISTORY_SIZE * CMD_BUFFER_SIZE) db 0
history_count: dd 0
history_index: dd 0

; save command to history
save_to_history:
    pusha
    
    ; don't save empty commands
    cmp dword [cmd_length], 0
    je .done
    
    ; get history slot
    mov eax, [history_count]
    cmp eax, HISTORY_SIZE
    jl .not_full
    mov eax, HISTORY_SIZE - 1
    .not_full:
    
    ; copy command to history
    mov ecx, [cmd_length]
    inc ecx                 ; include null terminator
    mov esi, cmd_buffer
    mov edi, history_buffer
    mov ebx, eax
    imul ebx, CMD_BUFFER_SIZE
    add edi, ebx
    rep movsb
    
    ; increment count
    cmp dword [history_count], HISTORY_SIZE
    jge .done
    inc dword [history_count]
    
    .done:
        popa
        ret

; load command from history
; EAX = history index
load_from_history:
    pusha
    
    ; bounds check
    cmp eax, [history_count]
    jge .done
    
    ; clear current line
    mov ecx, [cmd_length]
    .clear_loop:
        test ecx, ecx
        jz .clear_done
        dec dword [cursor_x]
        mov al, ' '
        call print_char
        dec dword [cursor_x]
        dec ecx
        jmp .clear_loop
    .clear_done:
    
    ; copy from history
    mov esi, history_buffer
    mov ebx, [history_index]
    imul ebx, CMD_BUFFER_SIZE
    add esi, ebx
    mov edi, cmd_buffer
    xor ecx, ecx
    .copy_loop:
        lodsb
        test al, al
        jz .copy_done
        stosb
        inc ecx
        cmp ecx, CMD_BUFFER_SIZE-1
        jge .copy_done
        jmp .copy_loop
    .copy_done:
    mov byte [edi], 0
    mov [cmd_length], ecx
    mov [cmd_position], ecx
    
    ; print the command
    mov esi, cmd_buffer
    call print_string
    
    .done:
        popa
        ret

shell_main:
    ; show the prompt
    mov esi, msg_prompt
    call print_string
    
    .loop:
        ; get a char from keyboard
        call getchar_wait
        
        ; check for arrow keys
        cmp al, 1           ; up arrow
        je .history_up
        cmp al, 4           ; down arrow
        je .history_down
        
        ; did they hit enter?
        cmp al, 13
        je .execute
        
        ; backspace?
        cmp al, 8
        je .backspace
        
        ; ignore other special chars
        cmp al, 32
        jl .loop
        
        ; add to command buffer at cursor position
        mov ebx, [cmd_length]
        cmp ebx, CMD_BUFFER_SIZE-1
        jge .loop
        
        mov [cmd_buffer + ebx], al
        inc dword [cmd_length]
        inc dword [cmd_position]
        
        ; echo it
        call print_char
        jmp .loop
    
    .history_up:
        ; go back in history
        cmp dword [history_count], 0
        je .loop
        mov eax, [history_index]
        cmp eax, [history_count]
        jge .loop
        inc dword [history_index]
        mov eax, [history_count]
        sub eax, [history_index]
        call load_from_history
        jmp .loop
    
    .history_down:
        ; go forward in history
        cmp dword [history_index], 0
        je .loop
        dec dword [history_index]
        cmp dword [history_index], 0
        jne .load_hist
        ; if at 0, clear line
        mov ecx, [cmd_length]
        .clear_down:
            test ecx, ecx
            jz .cleared
            dec dword [cursor_x]
            mov al, ' '
            call print_char
            dec dword [cursor_x]
            dec ecx
            jmp .clear_down
        .cleared:
            mov dword [cmd_length], 0
            mov dword [cmd_position], 0
            jmp .loop
        .load_hist:
            mov eax, [history_count]
            sub eax, [history_index]
            call load_from_history
            jmp .loop
    
    .backspace:
        cmp dword [cmd_length], 0
        je .loop
        
        dec dword [cmd_length]
        dec dword [cmd_position]
        
        ; move cursor back
        dec dword [cursor_x]
        
        ; print space over the char
        mov al, ' '
        call print_char
        
        ; move cursor back again
        dec dword [cursor_x]
        call update_cursor
        jmp .loop
    
    .execute:
        ; newline
        mov al, 10
        call print_char
        
        ; null terminate
        mov ebx, [cmd_length]
        mov byte [cmd_buffer + ebx], 0
        
        ; save to history
        call save_to_history
        
        ; run whatever they typed
        call process_command
        
        ; reset buffer and history position
        mov dword [cmd_length], 0
        mov dword [cmd_position], 0
        mov dword [history_index], 0
        
        ; show prompt again
        mov esi, msg_prompt
        call print_string
        jmp .loop

process_command:
    ; nothing typed? whatever
    cmp dword [cmd_length], 0
    je .done
    
    ; normalize command - allow with or without colon
    mov al, [cmd_buffer]
    cmp al, ':'
    je .has_colon
    
    ; shift buffer right to add colon at start (with safety check)
    mov ecx, [cmd_length]
    cmp ecx, CMD_BUFFER_SIZE-2  ; make sure we have room for : and null
    jge .has_colon              ; skip if buffer would overflow
    
    inc ecx
    mov esi, cmd_buffer
    add esi, ecx
    mov edi, esi
    dec edi
    .shift_loop:
        mov al, [esi]
        mov [edi], al
        dec esi
        dec edi
        dec ecx
        jnz .shift_loop
    mov byte [cmd_buffer], ':'
    inc dword [cmd_length]
    
    .has_colon:
    
    ; is it ":help"? (or just "help")
    mov esi, cmd_buffer
    mov edi, cmd_help
    call strcmp
    test eax, eax
    jz .show_help
    
    ; is it ":clear" or "cls"?
    mov esi, cmd_buffer
    mov edi, cmd_clear
    call strcmp
    test eax, eax
    jz .do_clear
    
    mov esi, cmd_buffer
    mov edi, cmd_cls
    call strcmp
    test eax, eax
    jz .do_clear
    
    ; is it ":time"?
    mov esi, cmd_buffer
    mov edi, cmd_time
    call strcmp
    test eax, eax
    jz .show_time
    
    ; is it ":mem"?
    mov esi, cmd_buffer
    mov edi, cmd_mem
    call strcmp
    test eax, eax
    jz .show_mem
    
    ; is it ":reboot"?
    mov esi, cmd_buffer
    mov edi, cmd_reboot
    call strcmp
    test eax, eax
    jz .do_reboot
    
    ; is it ":ver"?
    mov esi, cmd_buffer
    mov edi, cmd_ver
    call strcmp
    test eax, eax
    jz .show_ver
    
    ; is it ":datetime"?
    mov esi, cmd_buffer
    mov edi, cmd_datetime
    call strcmp
    test eax, eax
    jz .show_datetime
    
    ; is it ":timezone"?
    mov esi, cmd_buffer
    mov edi, cmd_timezone
    mov ecx, 10
    call strncmp
    test eax, eax
    jz .set_timezone
    
    ; is it ":pci"?
    mov esi, cmd_buffer
    mov edi, cmd_pci
    call strcmp
    test eax, eax
    jz .scan_pci_bus
    
    ; is it ":malloc"?
    mov esi, cmd_buffer
    mov edi, cmd_malloc
    call strcmp
    test eax, eax
    jz .test_malloc
    
    ; is it ":vmm"?
    mov esi, cmd_buffer
    mov edi, cmd_vmm
    call strcmp
    test eax, eax
    jz .test_vmm
    
    ; is it ":vmalloc"?
    mov esi, cmd_buffer
    mov edi, cmd_vmalloc
    call strcmp
    test eax, eax
    jz .vmm_alloc
    
    ; is it ":vmap"?
    mov esi, cmd_buffer
    mov edi, cmd_vmap
    call strcmp
    test eax, eax
    jz .vmm_map
    
    ; is it ":compress"?
    mov esi, cmd_buffer
    mov edi, cmd_compress
    call strcmp
    test eax, eax
    jz .vmm_compress_test
    
    ; is it ":decompress"?
    mov esi, cmd_buffer
    mov edi, cmd_decompress
    call strcmp
    test eax, eax
    jz .vmm_decompress_test
    
    ; is it ":paging"?
    mov esi, cmd_buffer
    mov edi, cmd_paging
    call strcmp
    test eax, eax
    jz .enable_paging
    
    ; is it ":free"?
    mov esi, cmd_buffer
    mov edi, cmd_free
    call strcmp
    test eax, eax
    jz .test_free
    
    ; is it ":syscall"?
    mov esi, cmd_buffer
    mov edi, cmd_syscall
    call strcmp
    test eax, eax
    jz .test_syscall
    
    ; is it ":tasks"?
    mov esi, cmd_buffer
    mov edi, cmd_tasks
    call strcmp
    test eax, eax
    jz .show_tasks
    
    ; is it ":net"?
    mov esi, cmd_buffer
    mov edi, cmd_net
    call strcmp
    test eax, eax
    jz .init_network
    
    ; is it ":pages"?
    mov esi, cmd_buffer
    mov edi, cmd_pages
    call strcmp
    test eax, eax
    jz .show_pages
    
    ; is it ":swap"?
    mov esi, cmd_buffer
    mov edi, cmd_swap
    call strcmp
    test eax, eax
    jz .show_swap
    
    ; is it ":netstats"?
    mov esi, cmd_buffer
    mov edi, cmd_netstats
    call strcmp
    test eax, eax
    jz .show_netstats
    
    ; is it ":gfx"?
    mov esi, cmd_buffer
    mov edi, cmd_gfx
    mov ecx, 4
    call strncmp
    test eax, eax
    jz .do_gfx
    
    ; is it ":gui"?
    mov esi, cmd_buffer
    mov edi, cmd_gui
    mov ecx, 4
    call strncmp
    test eax, eax
    jz .do_gui
    
    ; is it ":text"?
    mov esi, cmd_buffer
    mov edi, cmd_text
    mov ecx, 5
    call strncmp
    test eax, eax
    jz .do_text
    
    ; is it ":ping"?
    mov esi, cmd_buffer
    mov edi, cmd_ping
    mov ecx, 6              ; check first 6 chars ":ping "
    call strncmp
    test eax, eax
    jz .do_ping
    
    ; is it ":say"?
    mov esi, cmd_buffer
    mov edi, cmd_say
    mov ecx, 5              ; check first 5 chars ":say "
    call strncmp
    test eax, eax
    jz .do_say
    
    ; is it ":beep"?
    mov esi, cmd_buffer
    mov edi, cmd_beep
    call strcmp
    test eax, eax
    jz .do_beep
    
    ; is it ":loadnet"? (temporarily disabled)
    ; mov esi, cmd_buffer
    ; mov edi, cmd_loadnet
    ; call strcmp
    ; test eax, eax
    ; jz .do_loadnet
    
    ; is it ":format"?
    mov esi, cmd_buffer
    mov edi, cmd_format
    mov ecx, 7
    call strncmp
    test eax, eax
    jz .do_format
    
    ; is it ":mount"?
    mov esi, cmd_buffer
    mov edi, cmd_mount
    mov ecx, 6
    call strncmp
    test eax, eax
    jz .do_mount
    
    ; :list or :show or :ls
    mov esi, cmd_buffer
    mov edi, cmd_list
    mov ecx, 5
    call strncmp
    test eax, eax
    jz .fs_list
    
    mov esi, cmd_buffer
    mov edi, cmd_show
    mov ecx, 5
    call strncmp
    test eax, eax
    jz .fs_list
    
    mov esi, cmd_buffer
    mov edi, cmd_ls
    mov ecx, 3
    call strncmp
    test eax, eax
    jz .fs_list
    
    ; :make or :create
    mov esi, cmd_buffer
    mov edi, cmd_make
    mov ecx, 6
    call strncmp
    test eax, eax
    jz .fs_create
    
    mov esi, cmd_buffer
    mov edi, cmd_create
    mov ecx, 8
    call strncmp
    test eax, eax
    jz .fs_create
    
    ; :read or :open or :cat
    mov esi, cmd_buffer
    mov edi, cmd_read
    mov ecx, 6
    call strncmp
    test eax, eax
    jz .fs_read
    
    mov esi, cmd_buffer
    mov edi, cmd_open
    mov ecx, 6
    call strncmp
    test eax, eax
    jz .fs_read
    
    mov esi, cmd_buffer
    mov edi, cmd_cat
    mov ecx, 5
    call strncmp
    test eax, eax
    jz .fs_read
    
    ; :write
    mov esi, cmd_buffer
    mov edi, cmd_write
    mov ecx, 7
    call strncmp
    test eax, eax
    jz .fs_write
    
    ; :delete or :remove or :del or :rm
    mov esi, cmd_buffer
    mov edi, cmd_delete
    mov ecx, 8
    call strncmp
    test eax, eax
    jz .fs_delete
    
    mov esi, cmd_buffer
    mov edi, cmd_remove
    mov ecx, 8
    call strncmp
    test eax, eax
    jz .fs_delete
    
    mov esi, cmd_buffer
    mov edi, cmd_del
    mov ecx, 5
    call strncmp
    test eax, eax
    jz .fs_delete
    
    mov esi, cmd_rm
    mov ecx, 4
    call strncmp
    test eax, eax
    jz .fs_delete
    
    ; :edit or :vi or :nano (for the nerds)
    mov esi, cmd_buffer
    mov edi, cmd_edit
    mov ecx, 6
    call strncmp
    test eax, eax
    jz .do_edit
    
    mov esi, cmd_buffer
    mov edi, cmd_vi
    mov ecx, 4
    call strncmp
    test eax, eax
    jz .do_edit
    
    mov esi, cmd_buffer
    mov edi, cmd_nano
    mov ecx, 6
    call strncmp
    test eax, eax
    jz .do_edit
    
    ; unknown command (user is an idiot)
    mov esi, msg_unknown
    call print_string
    jmp .done
        jmp .done
    
    .show_help:
        mov esi, msg_help_text
        call print_string
        jmp .done
    
    .do_clear:
        call clear_screen
        jmp .done
    
    .show_time:
        mov esi, msg_time_text
        call print_string
        mov eax, [timer_ticks]
        call print_hex
        mov al, 10
        call print_char
        jmp .done
    
    .show_mem:
        mov esi, msg_mem_text
        call print_string
        jmp .done
    
    .show_datetime:
        call print_datetime
        jmp .done
    
    .set_timezone:
        ; check if there's an offset specified
        cmp dword [cmd_length], 11
        jl .show_current_tz
        
        ; parse the offset (+/-n)
        mov esi, cmd_buffer
        add esi, 10             ; skip ":timezone "
        
        ; check for sign
        lodsb
        cmp al, '-'
        je .negative_tz
        cmp al, '+'
        je .positive_tz
        
        ; no sign, assume positive
        dec esi
        
        .positive_tz:
            lodsb
            sub al, '0'
            mov [timezone_offset], al
            mov esi, msg_tz_set
            call print_string
            jmp .done
        
        .negative_tz:
            lodsb
            sub al, '0'
            neg al
            mov [timezone_offset], al
            mov esi, msg_tz_set
            call print_string
            jmp .done
        
        .show_current_tz:
            mov esi, msg_tz_current
            call print_string
            movsx eax, byte [timezone_offset]
            test eax, eax
            jge .tz_positive
            neg eax
            mov al, '-'
            call print_char
            movsx eax, byte [timezone_offset]
            neg eax
            jmp .tz_print
            .tz_positive:
                mov al, '+'
                call print_char
                movsx eax, byte [timezone_offset]
            .tz_print:
            call print_decimal
            mov al, 10
            call print_char
            jmp .done
    
    .scan_pci_bus:
        call scan_pci
        jmp .done
    
    .test_vmm:
        call vmm_show_stats
        jmp .done
    
    .vmm_alloc:
        mov esi, msg_vmm_test_alloc
        call print_string
        mov ecx, 0x4000             ; Allocate 16KB
        call vmm_alloc
        test eax, eax
        jz .vmm_alloc_fail
        call print_hex
        mov esi, msg_ok_alloc
        call print_string
        jmp .done
        .vmm_alloc_fail:
            mov esi, msg_vmm_fail
            call print_string
            jmp .done
    
    .vmm_map:
        mov esi, msg_vmm_test_map
        call print_string
        mov eax, 0x800000           ; Virtual address
        call vmm_alloc_frame        ; Get physical frame
        test eax, eax
        jz .vmm_map_fail
        mov ebx, eax                ; Physical address
        mov eax, 0x800000           ; Virtual address
        mov ecx, (VMM_PRESENT | VMM_WRITABLE | VMM_USER)
        call vmm_map_page
        mov esi, msg_vmm_mapped
        call print_string
        jmp .done
        .vmm_map_fail:
            mov esi, msg_vmm_fail
            call print_string
            jmp .done
    
    .vmm_compress_test:
        mov esi, msg_vmm_compress_test
        call print_string
        
        ; Allocate a page
        mov ecx, 0x1000
        call vmm_alloc
        test eax, eax
        jz .vmm_compress_fail
        mov [test_vmm_page], eax
        
        ; Fill with pattern (lots of repeated bytes for compression)
        mov edi, eax
        mov ecx, 1024
        mov eax, 0xAAAAAAAA
        rep stosd
        
        ; Get page index and mark as cold
        mov eax, [test_vmm_page]
        shr eax, 12
        mov esi, eax
        shl esi, 4
        add esi, vmm_page_tracking
        mov byte [esi], PAGE_COLD
        mov word [esi + 2], VMM_COMPRESS_THRESHOLD
        
        ; Compress the page
        call vmm_compress_page
        
        mov esi, msg_vmm_compressed_ok
        call print_string
        call vmm_show_stats
        jmp .done
        
        .vmm_compress_fail:
            mov esi, msg_vmm_fail
            call print_string
            jmp .done
    
    .vmm_decompress_test:
        mov esi, msg_vmm_decompress_test
        call print_string
        
        ; Access the compressed page (triggers decompression)
        mov eax, [test_vmm_page]
        shr eax, 12
        call vmm_page_accessed
        
        mov esi, msg_vmm_decompressed_ok
        call print_string
        call vmm_show_stats
        jmp .done
    
    .enable_paging:
        mov esi, msg_paging_enable
        call print_string
        call vmm_enable_paging
        mov esi, msg_paging_enabled
        call print_string
        jmp .done
    
    .test_malloc:
        mov esi, msg_malloc_header
        call print_string
        
        ; Test 1: Small allocation (256 bytes)
        mov esi, msg_malloc_test1
        call print_string
        mov ecx, 256
        call malloc
        test eax, eax
        jz .malloc_fail
        mov [test_ptr1], eax
        call print_hex
        mov esi, msg_ok_alloc
        call print_string
        
        ; Test 2: Medium allocation (4KB)
        mov esi, msg_malloc_test2
        call print_string
        mov ecx, 4096
        call malloc
        test eax, eax
        jz .malloc_fail
        mov [test_ptr2], eax
        call print_hex
        mov esi, msg_ok_alloc
        call print_string
        
        ; Test 3: Large allocation (64KB)
        mov esi, msg_malloc_test3
        call print_string
        mov ecx, 65536
        call malloc
        test eax, eax
        jz .malloc_fail
        mov [test_ptr3], eax
        call print_hex
        mov esi, msg_ok_alloc
        call print_string
        
        ; Test 4: Free allocations
        mov esi, msg_malloc_free
        call print_string
        mov eax, [test_ptr1]
        call free
        mov eax, [test_ptr2]
        call free
        mov eax, [test_ptr3]
        call free
        mov esi, msg_malloc_freed
        call print_string
        
        ; Test 5: Reallocate to test reuse
        mov esi, msg_malloc_realloc
        call print_string
        mov ecx, 512
        call malloc
        test eax, eax
        jz .malloc_fail
        call print_hex
        mov esi, msg_ok_alloc
        call print_string
        
        mov esi, msg_malloc_success
        call print_string
        jmp .done
        
    .malloc_fail:
        mov esi, msg_malloc_failed
        call print_string
        jmp .done
    
    .test_free:
        mov esi, msg_free_test
        call print_string
        jmp .done
    
    .test_syscall:
        mov esi, msg_syscall_test
        call print_string
        ; test syscall 1 (print)
        mov eax, SYSCALL_PRINT
        mov ebx, msg_syscall_hello
        int 0x80
        jmp .done
    
    .show_tasks:
        mov esi, msg_tasks_header
        call print_string
        
        ; print task count
        mov esi, msg_task_count
        call print_string
        mov eax, [task_count]
        call print_decimal
        mov al, 10
        call print_char
        
        ; print current task
        mov esi, msg_current_task
        call print_string
        mov eax, [current_task]
        call print_decimal
        mov al, 10
        call print_char
        jmp .done
    
    .init_network:
        call init_rtl8139
        call init_rtl8139_network
        call show_network_stats
        jmp .done
    
    .show_pages:
        call get_page_stats
        jmp .done
    
    .show_swap:
        call show_swap_info
        jmp .done
    
    .show_netstats:
        call show_network_stats
        jmp .done
    
    .do_gfx:
        ; switch to graphics mode
        call set_graphics_mode
        call graphics_demo
        jmp .done
    
    .do_gui:
        ; GUI demo - simple window display
        call set_graphics_mode
        ; call init_mouse  ; Skip mouse init for now
        call gui_demo
        jmp .done
    
    .do_text:
        ; go back to text mode
        call set_text_mode
        
        ; re-initialize text mode display
        call clear_screen
        mov esi, msg_text_mode
        call print_string
        jmp .done
    
    .do_ping:
        ; Parse IP address from command
        ; For now, just ping gateway (10.0.2.1)
        mov eax, [GATEWAY_IP]
        call send_ping
        mov esi, msg_ping_sent
        call print_string
        jmp .done
    
    .do_reboot:
        mov esi, msg_reboot_text
        call print_string
        ; wait a sec
        mov ecx, 100000000
        .reboot_wait:
            nop
            loop .reboot_wait
        ; triple fault reboot
        cli
        lidt [null_idt]
        int 3
    
    .show_ver:
        mov esi, msg_ver_text
        call print_string
        jmp .done
    
    .do_say:
        ; check if there's text after ":say "
        cmp dword [cmd_length], 5
        jle .done
        
        ; print text with echo effect
        mov esi, cmd_buffer
        add esi, 5              ; skip ":say "
        
        .say_loop:
            lodsb
            test al, al
            jz .say_echo
            
            ; print char
            call print_char
            
            ; small delay for dramatic effect
            push ecx
            mov ecx, 5000000
            .say_delay:
                nop
                loop .say_delay
            pop ecx
            jmp .say_loop
        
        .say_echo:
            ; newline
            mov al, 10
            call print_char
            
            ; print echo
            mov esi, msg_echo
            call print_string
            
            ; print it again but quieter (same text)
            mov esi, cmd_buffer
            add esi, 5
            call print_string
            
            ; more echoes
            mov al, 10
            call print_char
            mov esi, msg_echo
            call print_string
            
            mov esi, cmd_buffer
            add esi, 5
            call print_string
            
            mov al, 10
            call print_char
            jmp .done
    
    .do_beep:
        ; play a beep sound
        call beep
        mov esi, msg_beep_done
        call print_string
        jmp .done
    
    ; .do_loadnet:
        ; load network extensions module
        ; mov esi, msg_loadnet_loading
        ; call print_string
        ; 
        ; check if already loaded
        ; cmp byte [netext_loaded], 1
        ; je .net_already_loaded
        ; 
        ; simulate loading from disk (in real implementation would read netext.bin)
        ; for now, just set a flag and show success
        ; mov byte [netext_loaded], 1
        ; mov dword [netext_base], 0x50000
        ; 
        ; mov esi, msg_loadnet_success
        ; call print_string
        ; mov esi, msg_loadnet_info
        ; call print_string
        ; jmp .done
        ; 
    ; .net_already_loaded:
        ; mov esi, msg_loadnet_already
        ; call print_string
        ; jmp .done
    
    .do_format:
        ; format disk with J3KFS
        mov esi, msg_formatting
        call print_string
        call format_j3kfs
        mov esi, msg_fs_formatted
        call print_string
        jmp .done
    
    .do_mount:
        ; mount J3KFS
        call mount_j3kfs
        jmp .done
    
    .fs_list:
        ; list J3KFS directory
        mov eax, [current_dir_inode]
        call list_directory
        jmp .done
    
    .fs_create:
        ; check if filename provided
        cmp dword [cmd_length], 7
        jle .fs_create_no_name
        
        ; get filename (skip ":make " or ":create ")
        mov esi, cmd_buffer
        add esi, 6
        cmp byte [cmd_buffer + 1], 'c'  ; :create is longer
        jne .fs_create_go
        add esi, 2  ; skip 2 more chars
        
        .fs_create_go:
            ; create file in J3KFS
            call create_file
            cmp eax, -1
            je .fs_create_full
            
            mov esi, msg_file_created
            call print_string
            jmp .done
        
        .fs_create_no_name:
            mov esi, msg_fs_need_name
            call print_string
            jmp .done
        
        .fs_create_full:
            mov esi, msg_fs_full
            call print_string
            jmp .done
    
    .fs_read:
        ; check if filename provided
        cmp dword [cmd_length], 6
        jle .fs_read_no_name
        
        ; get filename (skip ":read " or ":open ")
        mov esi, cmd_buffer
        add esi, 6
        
        ; find file in J3KFS
        mov eax, [current_dir_inode]
        mov ebx, esi
        call find_dir_entry
        cmp eax, -1
        je .fs_read_not_found
        
        ; read file content
        mov edi, file_read_buffer
        mov ecx, 4096
        call read_file
        
        ; print content
        mov esi, msg_file_reading
        call print_string
        
        mov esi, file_read_buffer
        call print_string
        
        mov al, 10
        call print_char
        jmp .done
        
        .fs_read_not_found:
            mov esi, msg_file_not_found
            call print_string
            jmp .done
        
        .fs_read_no_name:
            mov esi, msg_fs_need_name
            call print_string
            jmp .done
    
    .fs_write:
        ; check if filename provided
        cmp dword [cmd_length], 8
        jle .fs_write_no_name
        
        ; parse ":write <filename> <text>"
        mov esi, cmd_buffer
        add esi, 7          ; skip ":write "
        
        ; find space to get filename
        mov edi, file_read_buffer
        mov ecx, 64
        .fs_write_copy_name:
            lodsb
            cmp al, ' '
            je .fs_write_got_name
            test al, al
            jz .fs_write_no_text
            stosb
            loop .fs_write_copy_name
        
        .fs_write_got_name:
            xor al, al
            stosb
            
            ; now esi points to the text to write
            mov [.text_ptr], esi
            
            ; calculate text length
            mov edi, esi
            xor ecx, ecx
            .fs_write_len:
                mov al, [edi]
                test al, al
                jz .fs_write_len_done
                inc ecx
                inc edi
                jmp .fs_write_len
            
            .fs_write_len_done:
            mov [.text_len], ecx
            
            ; find or create file
            mov eax, [current_dir_inode]
            mov ebx, file_read_buffer
            call find_dir_entry
            cmp eax, -1
            jne .fs_write_exists
            
            ; create new file
            mov esi, file_read_buffer
            call create_file
            cmp eax, -1
            je .fs_write_failed
            
            .fs_write_exists:
            ; write data to file
            mov esi, [.text_ptr]
            mov ecx, [.text_len]
            call write_file
            
            mov esi, msg_file_written
            call print_string
            call print_hex
            mov esi, msg_bytes_written
            call print_string
            jmp .done
        
        .fs_write_no_text:
        .fs_write_no_name:
            mov esi, msg_fs_need_name
            call print_string
            jmp .done
        
        .fs_write_failed:
            mov esi, msg_fs_full
            call print_string
            jmp .done
        
        .text_ptr: dd 0
        .text_len: dd 0
    
    .fs_delete:
        ; check if filename provided
        cmp dword [cmd_length], 8
        jle .fs_delete_no_name
        
        ; get filename (skip ":delete " or ":remove ")
        mov esi, cmd_buffer
        add esi, 8
        
        ; delete file from J3KFS
        call delete_file
        cmp eax, -1
        je .fs_delete_not_found
        
        mov esi, msg_file_deleted
        call print_string
        jmp .done
        
        .fs_delete_not_found:
            mov esi, msg_file_not_found
            call print_string
            jmp .done
        
        .fs_delete_no_name:
            mov esi, msg_fs_need_name
            call print_string
            jmp .done
    
    .do_edit:
        ; check if filename provided
        cmp dword [cmd_length], 6
        jle .edit_new_file
        
        ; get filename (skip ":edit " or ":vi " or ":nano ")
        mov esi, cmd_buffer
        add esi, 6
        
        ; skip any extra spaces
        .skip_spaces:
            lodsb
            cmp al, ' '
            je .skip_spaces
            dec esi
        
        call editor_main
        
        ; redraw screen after editor
        call clear_screen
        mov esi, msg_ready
        call print_string
        jmp .done
        
        .edit_new_file:
            xor esi, esi        ; null for new file
            call editor_main
            call clear_screen
            mov esi, msg_ready
            call print_string
            jmp .done
    
    .done:
        ret

strcmp:
    ; ESI = str1, EDI = str2
    ; returns 0 in EAX if they match
    pusha
    .loop:
        lodsb
        mov bl, [edi]
        inc edi
        cmp al, bl
        jne .not_equal
        test al, al
        jz .equal
        jmp .loop
    .equal:
        mov dword [esp+28], 0  ; they match
        popa
        ret
    .not_equal:
        mov dword [esp+28], 1  ; nope
        popa
        ret

strncmp:
    ; ESI = str1, EDI = str2, ECX = length
    ; returns 0 in EAX if first n chars match
    pusha
    .loop:
        test ecx, ecx
        jz .equal
        lodsb
        mov bl, [edi]
        inc edi
        cmp al, bl
        jne .not_equal
        dec ecx
        jmp .loop
    .equal:
        mov dword [esp+28], 0  ; they match
        popa
        ret
    .not_equal:
        mov dword [esp+28], 1  ; nope
        popa
        ret

strcmp_simple:
    ; ESI = str1, EDI = str2 (on stack)
    ; returns 0 in EAX if match
    .loop:
        mov al, [esi]
        mov bl, [edi]
        cmp al, bl
        jne .not_equal
        test al, al
        jz .equal
        cmp al, ' '
        je .equal
        inc esi
        inc edi
        jmp .loop
    .equal:
        xor eax, eax
        ret
    .not_equal:
        mov eax, 1
        ret

; ========================================
; DATA N MESSAGES
; ========================================
msg_boot:       db 'j3kOS 32-bit Protected Mode', 10
                db 'by Jortboy3k (@jortboy3k)', 10, 10, 0
msg_safe_mode:  db '[SAFE MODE]', 10, 0
msg_verbose_mode: db '[VERBOSE MODE]', 10, 0
msg_init_idt_ok: db '[INIT] IDT OK', 10, 0
msg_init_pic_ok: db '[INIT] PIC OK', 10, 0
msg_init_pit_ok: db '[INIT] PIT OK', 10, 0
msg_init_kb_ok:  db '[INIT] Keyboard OK', 10, 0
msg_init_tss_ok: db '[INIT] TSS OK', 10, 0
msg_init_page_ok: db '[INIT] Page Mgmt OK', 10, 0
msg_ready:      db 'System ready. Type "help" for commands.', 10, 10, 0
msg_prompt:     db '> ', 0
msg_unknown:    db 'Unknown command. Type "help" for list.', 10, 0
msg_help_text:  db 'j3kOS Help Menu', 10
                db '===============', 10, 10
                db '[System]', 10
                db '  help, clear, ver, reboot', 10
                db '  time, datetime, timezone', 10
                db '  mem, pci, tasks, syscall', 10, 10
                db '[Filesystem]', 10
                db '  ls, cat <f>, edit <f>', 10
                db '  make <f>, del <f>', 10
                db '  write <f> <t>', 10
                db '  format, mount', 10, 10
                db '[Network]', 10
                db '  net, netstats, ping <ip>', 10
                db '  loadnet', 10, 10
                db '[Memory]', 10
                db '  malloc, free, vmm', 10
                db '  vmalloc, vmap, paging', 10
                db '  pages, swap', 10
                db '  compress, decompress', 10, 10
                db '[Media/GUI]', 10
                db '  gfx, gui, text', 10
                db '  beep, say <text>', 10, 10
                db "Type commands with or without ':'", 10, 0
msg_time_text:  db 'Timer ticks: 0x', 0
msg_mem_text:   db '32MB ram, kernel @ 0x10000, stack @ 0x90000', 10, 0
msg_reboot_text: db 'rebooting...', 10, 0
msg_ping_sent:   db 'ping sent', 10, 0
msg_text_mode:   db 'text mode', 10, 0
msg_formatting:  db 'formatting...', 10, 0
msg_ver_text:   db 'j3kOS v1.0 by jortboy3k', 10, 0
msg_echo:       db '  ...', 0
msg_beep_done:  db 'beep!', 10, 0

; Network extension module messages
msg_loadnet_loading:    db 'Loading network extensions...', 10, 0
msg_loadnet_success:    db 'Network module loaded at 0x50000', 10, 0
msg_loadnet_info:       db 'Available: tcp, http, json, api commands', 10, 0
msg_loadnet_already:    db 'Network extensions already loaded', 10, 0

; file system messages
msg_fs_list_header: db 'Files:', 10, 0
msg_fs_bullet:      db '  - ', 0
msg_fs_no_files:    db '  (empty)', 10, 0
msg_fs_created:     db 'created', 10, 0
msg_fs_deleted:     db 'deleted', 10, 0
msg_fs_not_found:   db 'not found', 10, 0
msg_fs_need_name:   db 'need filename', 10, 0
msg_fs_full:        db 'disk full (16 max)', 10, 0
msg_fs_reading:     db 'Reading: ', 0
msg_fs_content:     db 10, '(file is empty)', 10, 0

cmd_help:       db ':help', 0
cmd_clear:      db ':clear', 0
cmd_time:       db ':time', 0
cmd_mem:        db ':mem', 0
cmd_reboot:     db ':reboot', 0
cmd_ver:        db ':ver', 0
cmd_datetime:   db ':datetime', 0
cmd_timezone:   db ':timezone ', 0
cmd_pci:        db ':pci', 0
cmd_malloc:     db ':malloc', 0
cmd_free:       db ':free', 0
cmd_vmm:        db ':vmm', 0
cmd_vmalloc:    db ':vmalloc', 0
cmd_vmap:       db ':vmap', 0
cmd_compress:   db ':compress', 0
cmd_decompress: db ':decompress', 0
cmd_paging:     db ':paging', 0
cmd_syscall:    db ':syscall', 0
cmd_tasks:      db ':tasks', 0
cmd_net:        db ':net', 0
cmd_pages:      db ':pages', 0
cmd_swap:       db ':swap', 0
cmd_netstats:   db ':netstats', 0
cmd_ping:       db ':ping', 0
cmd_gfx:        db ':gfx', 0
cmd_gui:        db ':gui', 0
cmd_text:       db ':text', 0
cmd_format:     db ':format', 0
cmd_mount:      db ':mount', 0
cmd_say:        db ':say ', 0
cmd_beep:       db ':beep', 0
cmd_loadnet:    db ':loadnet', 0

; Network extension module state
netext_loaded:  db 0
netext_base:    dd 0

msg_year_prefix: db '20', 0
msg_tz_set:     db 'Timezone offset set!', 10, 0
msg_tz_current: db 'Current timezone offset: ', 0
msg_malloc_header: db 'Memory Allocator Test Suite', 10, 0
msg_malloc_test1: db '  [1/5] Allocating 256 bytes...   0x', 0
msg_malloc_test2: db '  [2/5] Allocating 4096 bytes...  0x', 0
msg_malloc_test3: db '  [3/5] Allocating 65536 bytes... 0x', 0
msg_malloc_free:  db '  [4/5] Freeing all allocations...', 0
msg_malloc_freed: db ' OK', 10, 0
msg_malloc_realloc: db '  [5/5] Reallocating 512 bytes... 0x', 0
msg_ok_alloc:    db ' OK', 10, 0
msg_malloc_success: db 'All tests passed! Allocator working correctly.', 10, 0
msg_malloc_failed: db ' FAILED!', 10, 'Error: Out of memory or heap corruption.', 10, 0
msg_vmm_test_alloc: db 'Allocating 16KB virtual memory... 0x', 0
msg_vmm_test_map:   db 'Mapping page at 0x800000... ', 0
msg_vmm_mapped:     db 'OK - Page mapped successfully!', 10, 0
msg_vmm_fail:       db 'FAILED - Out of memory!', 10, 0
msg_vmm_compress_test: db 'Testing page compression (RLE)...', 10, 0
msg_vmm_compressed_ok: db 'Page compressed successfully!', 10, 0
msg_vmm_decompress_test: db 'Testing page decompression...', 10, 0
msg_vmm_decompressed_ok: db 'Page decompressed successfully!', 10, 0
msg_paging_enable: db 'Enabling hardware paging...', 10, 0
msg_paging_enabled: db 'Paging enabled! CR0.PG=1, CR3=0x00200000', 10, 0
test_ptr1: dd 0
test_ptr2: dd 0
test_ptr3: dd 0
test_vmm_page: dd 0
msg_free_test:  db 'Free is available (use with pointer)', 10, 0
msg_syscall_test: db 'Testing syscall interface...', 10, 0
msg_syscall_hello: db 'Syscall works! (printed via INT 0x80)', 10, 0
msg_tasks_header: db 'Task Status:', 10, 0
msg_task_count: db '  Total tasks: ', 0
msg_current_task: db '  Current task: ', 0

; file system commands
cmd_list:       db ':list', 0
cmd_show:       db ':show', 0
cmd_ls:         db ':ls', 0
cmd_cat:        db ':cat ', 0
cmd_make:       db ':make ', 0
cmd_create:     db ':create ', 0
cmd_read:       db ':read ', 0
cmd_open:       db ':open ', 0
cmd_write:      db ':write ', 0
cmd_delete:     db ':delete ', 0
cmd_remove:     db ':remove ', 0
cmd_del:        db ':del ', 0
cmd_rm:         db ':rm ', 0
cmd_cls:        db ':cls', 0
cmd_edit:       db ':edit ', 0
cmd_vi:         db ':vi ', 0
cmd_nano:       db ':nano ', 0

; IDT
align 16
idt_table: times 256*8 db 0
idt_descriptor:
    dw 256*8 - 1
    dd idt_table

; null IDT for rebooting
null_idt:
    dw 0
    dd 0

; ========================================
; FILE SYSTEM
; ========================================
MAX_FILES equ 16

file_count: dd 0
file_table: times (MAX_FILES * 32) db 0  ; 16 files, 32 bytes each (16 for name, 16 reserved)
file_read_buffer: times 4096 db 0        ; buffer for reading files

; ========================================
; END OF KERNEL MARKER
; ========================================
kernel_end:
