; ========================================
; RTC DRIVER - TIME AND DATE
; ========================================

RTC_PORT_CMD equ 0x70
RTC_PORT_DATA equ 0x71

rtc_print_time:
    pusha
    
    ; read time
    mov al, 0x04    ; hours
    call rtc_read
    call print_hex_byte
    
    mov al, ':'
    call print_char
    
    mov al, 0x02    ; minutes
    call rtc_read
    call print_hex_byte
    
    mov al, ':'
    call print_char
    
    mov al, 0x00    ; seconds
    call rtc_read
    call print_hex_byte
    
    mov al, ' '
    call print_char
    
    ; read date
    mov al, 0x07    ; day
    call rtc_read
    call print_hex_byte
    
    mov al, '/'
    call print_char
    
    mov al, 0x08    ; month
    call rtc_read
    call print_hex_byte
    
    mov al, '/'
    call print_char
    
    mov esi, msg_year_prefix
    call print_string
    
    mov al, 0x09    ; year
    call rtc_read
    call print_hex_byte
    
    mov al, 10
    call print_char
    
    popa
    ret

rtc_read:
    out RTC_PORT_CMD, al
    in al, RTC_PORT_DATA
    ret

msg_year_prefix: db '20', 0
