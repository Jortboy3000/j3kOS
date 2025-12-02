; ========================================
; LOGIN - SECURITY THEATER (fake as fuck)
; ========================================

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
        jne .got_user
        
        ; default to "guest"
        mov dword [login_username], 'gues'
        mov byte [login_username+4], 't'
        mov byte [login_username+5], 0
        
        .got_user:
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
        cmp al, 10      ; newline (just in case)
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
        cmp al, 10
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

login_username: times 32 db 0
login_password: times 32 db 0
msg_login_prompt: db 'j3kOS Login: ', 0
msg_pass_prompt:  db 'Password: ', 0
msg_login_fail:   db 'Login incorrect.', 10, 0
msg_welcome_user: db 'Welcome, ', 0
