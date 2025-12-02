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

msg_pci_scanning: db 'Scanning PCI bus...', 10, 0
msg_pci_found:    db '  ', 0
msg_pci_done:     db 'PCI scan complete.', 10, 0
