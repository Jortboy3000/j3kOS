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

; IRQ11 Handler - Network
irq11_handler:
    pusha
    
    ; Acknowledge interrupt (ISR register)
    mov edx, [rtl8139_io_base]
    add edx, RTL8139_ISR
    mov ax, 0xFFFF      ; Clear all bits
    out dx, ax
    
    ; Send EOI to PIC (slave)
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    
    popa
    iret
