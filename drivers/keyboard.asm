; ========================================
; KEYBOARD - SCAN CODES N SHIT
; ========================================
KEY_BUFFER_SIZE equ 256

key_buffer: times KEY_BUFFER_SIZE db 0
key_read_pos: dd 0
key_write_pos: dd 0
shift_pressed: db 0
caps_lock: db 0
num_lock: db 1          ; Default NumLock ON
extended_mode: db 0

; Numpad ASCII mapping (Scancodes 0x47-0x53)
; 7 8 9 - 4 5 6 + 1 2 3 0 .
numpad_chars: db '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '0', '.'

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
    
    ; check for num lock
    cmp al, 0x45
    je .num_lock_toggle
    
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
        cmp al, 0x4B        ; left arrow
        je .arrow_left
        cmp al, 0x4D        ; right arrow
        je .arrow_right
        jmp .done
        
        .arrow_up:
            mov al, 1       ; special code for up
            jmp .got_char
        .arrow_down:
            mov al, 4       ; special code for down
            jmp .got_char
        .arrow_left:
            mov al, 2       ; special code for left
            jmp .got_char
        .arrow_right:
            mov al, 3       ; special code for right
            jmp .got_char
    
    .convert_scancode:
    ; convert scancode to ASCII
    movzx ebx, al
    
    ; Check for Numpad keys (0x47 - 0x53)
    cmp al, 0x47
    jl .check_normal_table
    cmp al, 0x53
    jg .check_normal_table
    
    ; It is a numpad key
    cmp byte [num_lock], 1
    je .numpad_numbers
    
    ; NumLock OFF - Navigation
    cmp al, 0x48    ; Numpad 8 (Up)
    je .arrow_up
    cmp al, 0x50    ; Numpad 2 (Down)
    je .arrow_down
    jmp .done       ; Ignore other nav keys for now
    
    .numpad_numbers:
        sub al, 0x47
        movzx ebx, al
        mov al, [numpad_chars + ebx]
        jmp .got_char
        
    .check_normal_table:
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
        
    .num_lock_toggle:
        xor byte [num_lock], 1
        jmp .done
    
    .done:
        ; tell PIC we're done
        mov al, 0x20
        out 0x20, al
        
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
