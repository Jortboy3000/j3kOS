; =====================================================
; TEXT EDITOR - FULL-SCREEN EDITOR WITH SYNTAX
; making code editing actually usable
; =====================================================

; Editor constants
EDITOR_MAX_LINES    equ 500
EDITOR_LINE_SIZE    equ 80
EDITOR_SCREEN_ROWS  equ 23      ; 25 - 2 for status bars
EDITOR_TAB_SIZE     equ 4

; Editor state
editor_buffer:      times (EDITOR_MAX_LINES * EDITOR_LINE_SIZE) db 0
editor_line_count:  dd 0
editor_cursor_x:    dd 0
editor_cursor_y:    dd 0
editor_scroll_y:    dd 0
editor_modified:    db 0
editor_filename:    times 32 db 0
editor_insert_mode: db 1        ; 1 = insert, 0 = overwrite
editor_syntax_mode: db 0        ; 0 = none, 1 = asm, 2 = c

; Clipboard for copy/paste
clipboard_buffer:   times EDITOR_LINE_SIZE db 0
clipboard_length:   dd 0

; Syntax highlighting colors
SYNTAX_NORMAL       equ 0x07    ; light gray on black
SYNTAX_KEYWORD      equ 0x0E    ; yellow
SYNTAX_COMMENT      equ 0x0A    ; green
SYNTAX_STRING       equ 0x0C    ; red
SYNTAX_NUMBER       equ 0x0B    ; cyan
SYNTAX_DIRECTIVE    equ 0x0D    ; magenta

; ========================================
; EDITOR MAIN LOOP
; ========================================

; run the text editor
; ESI = filename to load (or 0 for new file)
editor_main:
    pusha
    
    ; save filename if provided
    test esi, esi
    jz .no_filename
    mov edi, editor_filename
    mov ecx, 32
    .copy_name:
        lodsb
        stosb
        test al, al
        jz .name_done
        loop .copy_name
    .name_done:
    
    ; try to load file
    mov esi, editor_filename
    call editor_load_file
    
    .no_filename:
    
    ; detect syntax mode from filename
    mov esi, editor_filename
    call editor_detect_syntax
    
    ; clear screen and draw initial view
    call clear_screen
    call editor_draw_screen
    
    .main_loop:
        ; draw the screen
        call editor_draw_screen
        
        ; get keypress
        call getchar_wait
        
        ; check for special keys
        cmp al, 27          ; ESC
        je .check_exit
        cmp al, 1           ; Up arrow
        je .cursor_up
        cmp al, 2           ; Down arrow
        je .cursor_down
        cmp al, 3           ; Left arrow
        je .cursor_left
        cmp al, 4           ; Right arrow
        je .cursor_right
        cmp al, 19          ; Ctrl+S (save)
        je .save_file
        cmp al, 24          ; Ctrl+X (cut line)
        je .cut_line
        cmp al, 3           ; Ctrl+C (copy line)
        je .copy_line
        cmp al, 22          ; Ctrl+V (paste)
        je .paste_line
        cmp al, 14          ; Ctrl+N (new line)
        je .new_line_below
        cmp al, 4           ; Ctrl+D (delete line)
        je .delete_line
        cmp al, 9           ; Tab
        je .insert_tab
        cmp al, 8           ; Backspace
        je .backspace
        cmp al, 13          ; Enter
        je .enter_key
        
        ; regular character - insert it
        cmp al, 32
        jl .main_loop       ; ignore control chars
        cmp al, 126
        jg .main_loop
        
        call editor_insert_char
        jmp .main_loop
    
    .check_exit:
        ; check if modified
        cmp byte [editor_modified], 1
        jne .do_exit
        
        ; ask to save
        call editor_show_save_prompt
        test eax, eax
        jz .do_exit
        
        call editor_save_file
        
    .do_exit:
        call clear_screen
        popa
        ret
    
    .cursor_up:
        call editor_move_up
        jmp .main_loop
    
    .cursor_down:
        call editor_move_down
        jmp .main_loop
    
    .cursor_left:
        call editor_move_left
        jmp .main_loop
    
    .cursor_right:
        call editor_move_right
        jmp .main_loop
    
    .save_file:
        call editor_save_file
        jmp .main_loop
    
    .cut_line:
        call editor_cut_line
        jmp .main_loop
    
    .copy_line:
        call editor_copy_line
        jmp .main_loop
    
    .paste_line:
        call editor_paste_line
        jmp .main_loop
    
    .new_line_below:
        call editor_insert_line_below
        jmp .main_loop
    
    .delete_line:
        call editor_delete_current_line
        jmp .main_loop
    
    .insert_tab:
        call editor_insert_tab
        jmp .main_loop
    
    .backspace:
        call editor_backspace
        jmp .main_loop
    
    .enter_key:
        call editor_split_line
        jmp .main_loop

; ========================================
; EDITOR DRAWING
; ========================================

editor_draw_screen:
    pusha
    
    ; draw status bar at top
    call editor_draw_status_bar
    
    ; draw line numbers and content
    mov dword [.row], 0
    
    .draw_loop:
        mov eax, [.row]
        cmp eax, EDITOR_SCREEN_ROWS
        jge .done_drawing
        
        ; calculate actual line number
        mov ebx, [editor_scroll_y]
        add ebx, eax
        
        ; check if line exists
        cmp ebx, [editor_line_count]
        jge .draw_empty_line
        
        ; draw line number
        mov [cursor_y], eax
        inc dword [cursor_y]    ; skip status bar
        mov dword [cursor_x], 0
        
        mov eax, ebx
        inc eax                 ; 1-based line numbers
        call editor_draw_line_number
        
        ; draw line content with syntax highlighting
        mov eax, ebx
        call editor_draw_line_content
        
        jmp .next_line
        
        .draw_empty_line:
            ; just draw tilde like vim
            mov eax, [.row]
            inc eax
            mov [cursor_y], eax
            mov dword [cursor_x], 0
            mov al, '~'
            mov ah, 0x08        ; dark gray
            call print_char_color
        
        .next_line:
        inc dword [.row]
        jmp .draw_loop
    
    .done_drawing:
    
    ; draw help bar at bottom
    call editor_draw_help_bar
    
    ; position cursor
    mov eax, [editor_cursor_y]
    sub eax, [editor_scroll_y]
    inc eax                     ; skip status bar
    mov [cursor_y], eax
    
    mov eax, [editor_cursor_x]
    add eax, 5                  ; skip line number area
    mov [cursor_x], eax
    
    popa
    ret
    
    .row: dd 0

editor_draw_status_bar:
    pusha
    
    ; position at top
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    
    ; draw filename or [New File]
    mov esi, editor_filename
    cmp byte [esi], 0
    jne .has_name
    mov esi, .new_file_text
    
    .has_name:
    mov ah, 0x70            ; black on white
    .name_loop:
        lodsb
        test al, al
        jz .name_done
        call print_char_color
        jmp .name_loop
    .name_done:
    
    ; show modified indicator
    cmp byte [editor_modified], 1
    jne .not_modified
    mov al, '*'
    mov ah, 0x70
    call print_char_color
    .not_modified:
    
    ; pad rest of line
    mov ecx, 80
    sub ecx, [cursor_x]
    mov al, ' '
    mov ah, 0x70
    .pad_loop:
        test ecx, ecx
        jz .pad_done
        call print_char_color
        dec ecx
        jmp .pad_loop
    .pad_done:
    
    popa
    ret
    
    .new_file_text: db '[New File]', 0

editor_draw_help_bar:
    pusha
    
    mov dword [cursor_x], 0
    mov dword [cursor_y], 24
    
    mov esi, .help_text
    mov ah, 0x70
    .loop:
        lodsb
        test al, al
        jz .done
        call print_char_color
        jmp .loop
    .done:
    
    ; pad rest
    mov ecx, 80
    sub ecx, [cursor_x]
    mov al, ' '
    .pad:
        test ecx, ecx
        jz .pad_done
        call print_char_color
        dec ecx
        jmp .pad
    .pad_done:
    
    popa
    ret
    
    .help_text: db 'ESC:Exit  ^S:Save  ^X:Cut  ^C:Copy  ^V:Paste  ^N:NewLine  ^D:DelLine', 0

editor_draw_line_number:
    ; EAX = line number to draw
    pusha
    
    ; draw line number (4 digits + space)
    mov ebx, eax
    
    ; digit 1 (thousands)
    mov eax, ebx
    xor edx, edx
    mov ecx, 1000
    div ecx
    add al, '0'
    mov ah, 0x08            ; dark gray
    call print_char_color
    
    ; digit 2 (hundreds)
    mov eax, edx
    xor edx, edx
    mov ecx, 100
    div ecx
    add al, '0'
    mov ah, 0x08
    call print_char_color
    
    ; digit 3 (tens)
    mov eax, edx
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    mov ah, 0x08
    call print_char_color
    
    ; digit 4 (ones)
    mov al, dl
    add al, '0'
    mov ah, 0x08
    call print_char_color
    
    ; space separator
    mov al, ' '
    mov ah, 0x07
    call print_char_color
    
    popa
    ret

editor_draw_line_content:
    ; EAX = line index to draw
    pusha
    
    ; get pointer to line
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov esi, editor_buffer
    add esi, eax
    
    ; check syntax mode
    cmp byte [editor_syntax_mode], 0
    je .no_syntax
    
    ; draw with syntax highlighting
    call editor_draw_line_syntax
    jmp .done
    
    .no_syntax:
    ; draw without syntax highlighting
    mov ecx, EDITOR_LINE_SIZE
    mov ah, SYNTAX_NORMAL
    .loop:
        lodsb
        test al, al
        jz .done
        cmp al, 32
        jl .done
        call print_char_color
        dec ecx
        jnz .loop
    
    .done:
    popa
    ret

editor_draw_line_syntax:
    ; ESI = line buffer
    ; Draw line with syntax highlighting
    pusha
    
    mov dword [.in_string], 0
    mov dword [.in_comment], 0
    
    .loop:
        lodsb
        test al, al
        jz .done
        cmp al, 32
        jl .done
        
        ; check for comment start
        cmp byte [editor_syntax_mode], 1    ; ASM
        jne .not_asm_comment
        cmp al, ';'
        jne .not_asm_comment
        mov dword [.in_comment], 1
        .not_asm_comment:
        
        ; if in comment, use comment color
        cmp dword [.in_comment], 1
        jne .not_in_comment
        mov ah, SYNTAX_COMMENT
        call print_char_color
        jmp .loop
        
        .not_in_comment:
        
        ; check for string
        cmp al, '"'
        jne .not_quote
        xor dword [.in_string], 1
        mov ah, SYNTAX_STRING
        call print_char_color
        jmp .loop
        .not_quote:
        
        cmp al, 39          ; single quote
        jne .not_squote
        xor dword [.in_string], 1
        mov ah, SYNTAX_STRING
        call print_char_color
        jmp .loop
        .not_squote:
        
        ; if in string, use string color
        cmp dword [.in_string], 1
        jne .not_in_string
        mov ah, SYNTAX_STRING
        call print_char_color
        jmp .loop
        .not_in_string:
        
        ; check for numbers
        cmp al, '0'
        jl .not_number
        cmp al, '9'
        jg .not_number
        mov ah, SYNTAX_NUMBER
        call print_char_color
        jmp .loop
        .not_number:
        
        ; check for directives (words starting with .)
        cmp al, '.'
        jne .not_directive
        mov ah, SYNTAX_DIRECTIVE
        call print_char_color
        jmp .loop
        .not_directive:
        
        ; check for keywords (simplified - just color known keywords)
        call editor_is_keyword_char
        test eax, eax
        jz .not_keyword_start
        
        ; look ahead for keyword
        push esi
        dec esi
        call editor_check_keyword
        pop esi
        test eax, eax
        jz .not_keyword
        
        mov ah, SYNTAX_KEYWORD
        call print_char_color
        jmp .loop
        
        .not_keyword:
        .not_keyword_start:
        
        ; default color
        mov ah, SYNTAX_NORMAL
        call print_char_color
        jmp .loop
    
    .done:
    popa
    ret
    
    .in_string: dd 0
    .in_comment: dd 0

editor_is_keyword_char:
    ; AL = character
    ; returns EAX = 1 if keyword char, 0 otherwise
    cmp al, 'a'
    jl .not_lower
    cmp al, 'z'
    jle .yes
    .not_lower:
    cmp al, 'A'
    jl .no
    cmp al, 'Z'
    jle .yes
    .no:
    xor eax, eax
    ret
    .yes:
    mov eax, 1
    ret

editor_check_keyword:
    ; ESI = position in line
    ; returns EAX = 1 if keyword, 0 otherwise
    push esi
    
    ; check common ASM keywords
    mov edi, .kw_mov
    call .check_word
    test eax, eax
    jnz .found
    
    mov edi, .kw_add
    call .check_word
    test eax, eax
    jnz .found
    
    mov edi, .kw_sub
    call .check_word
    test eax, eax
    jnz .found
    
    mov edi, .kw_call
    call .check_word
    test eax, eax
    jnz .found
    
    mov edi, .kw_ret
    call .check_word
    test eax, eax
    jnz .found
    
    mov edi, .kw_jmp
    call .check_word
    test eax, eax
    jnz .found
    
    xor eax, eax
    pop esi
    ret
    
    .found:
    mov eax, 1
    pop esi
    ret
    
    .check_word:
        ; ESI = position, EDI = keyword
        push esi
        .cmp_loop:
            mov al, [esi]
            mov bl, [edi]
            test bl, bl
            jz .word_end
            cmp al, bl
            jne .no_match
            inc esi
            inc edi
            jmp .cmp_loop
        .word_end:
            ; check next char is not alphanumeric
            mov al, [esi]
            call editor_is_keyword_char
            test eax, eax
            jnz .no_match
            mov eax, 1
            pop esi
            ret
        .no_match:
            xor eax, eax
            pop esi
            ret
    
    .kw_mov: db 'mov', 0
    .kw_add: db 'add', 0
    .kw_sub: db 'sub', 0
    .kw_call: db 'call', 0
    .kw_ret: db 'ret', 0
    .kw_jmp: db 'jmp', 0

; ========================================
; CURSOR MOVEMENT
; ========================================

editor_move_up:
    pusha
    cmp dword [editor_cursor_y], 0
    je .at_top
    dec dword [editor_cursor_y]
    
    ; adjust scroll if needed
    mov eax, [editor_cursor_y]
    cmp eax, [editor_scroll_y]
    jge .done
    dec dword [editor_scroll_y]
    jmp .done
    
    .at_top:
    .done:
    
    ; clamp cursor_x to line length
    call editor_clamp_cursor_x
    popa
    ret

editor_move_down:
    pusha
    mov eax, [editor_cursor_y]
    inc eax
    cmp eax, [editor_line_count]
    jge .at_bottom
    
    inc dword [editor_cursor_y]
    
    ; adjust scroll if needed
    mov eax, [editor_cursor_y]
    sub eax, [editor_scroll_y]
    cmp eax, EDITOR_SCREEN_ROWS
    jl .done
    inc dword [editor_scroll_y]
    jmp .done
    
    .at_bottom:
    .done:
    call editor_clamp_cursor_x
    popa
    ret

editor_move_left:
    pusha
    cmp dword [editor_cursor_x], 0
    je .at_start
    dec dword [editor_cursor_x]
    jmp .done
    
    .at_start:
    ; move to end of previous line
    cmp dword [editor_cursor_y], 0
    je .done
    dec dword [editor_cursor_y]
    call editor_get_line_length
    mov [editor_cursor_x], eax
    
    .done:
    popa
    ret

editor_move_right:
    pusha
    call editor_get_line_length
    cmp [editor_cursor_x], eax
    jge .at_end
    inc dword [editor_cursor_x]
    jmp .done
    
    .at_end:
    ; move to start of next line
    mov eax, [editor_cursor_y]
    inc eax
    cmp eax, [editor_line_count]
    jge .done
    inc dword [editor_cursor_y]
    mov dword [editor_cursor_x], 0
    
    .done:
    popa
    ret

editor_clamp_cursor_x:
    ; ensure cursor_x doesn't exceed line length
    pusha
    call editor_get_line_length
    cmp [editor_cursor_x], eax
    jle .done
    mov [editor_cursor_x], eax
    .done:
    popa
    ret

editor_get_line_length:
    ; returns line length in EAX
    pusha
    
    mov eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov esi, editor_buffer
    add esi, eax
    
    xor ecx, ecx
    .loop:
        lodsb
        test al, al
        jz .done
        cmp al, 32
        jl .done
        inc ecx
        cmp ecx, EDITOR_LINE_SIZE
        jge .done
        jmp .loop
    .done:
    mov [esp + 28], ecx     ; return in EAX
    popa
    ret

; ========================================
; EDITING OPERATIONS
; ========================================

editor_insert_char:
    ; AL = character to insert
    pusha
    
    mov [.char], al
    mov byte [editor_modified], 1
    
    ; get current line pointer
    mov eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    add edi, [editor_cursor_x]
    
    ; check if in insert mode
    cmp byte [editor_insert_mode], 1
    jne .overwrite
    
    ; shift rest of line right
    mov esi, edi
    add esi, EDITOR_LINE_SIZE - 1
    mov ecx, EDITOR_LINE_SIZE
    sub ecx, [editor_cursor_x]
    dec ecx
    .shift:
        test ecx, ecx
        jz .shift_done
        mov al, [esi - 1]
        mov [esi], al
        dec esi
        dec ecx
        jmp .shift
    .shift_done:
    
    .overwrite:
    mov al, [.char]
    mov [edi], al
    
    inc dword [editor_cursor_x]
    
    popa
    ret
    
    .char: db 0

editor_backspace:
    pusha
    
    cmp dword [editor_cursor_x], 0
    je .at_line_start
    
    mov byte [editor_modified], 1
    
    ; get current line pointer
    mov eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    add edi, [editor_cursor_x]
    dec edi                     ; move to char before cursor
    
    ; shift rest of line left
    mov esi, edi
    inc esi
    mov ecx, EDITOR_LINE_SIZE
    sub ecx, [editor_cursor_x]
    .shift:
        test ecx, ecx
        jz .shift_done
        mov al, [esi]
        mov [edi], al
        inc esi
        inc edi
        dec ecx
        jmp .shift
    .shift_done:
    
    dec dword [editor_cursor_x]
    jmp .done
    
    .at_line_start:
    ; TODO: merge with previous line
    
    .done:
    popa
    ret

editor_split_line:
    ; split current line at cursor (Enter key)
    pusha
    
    mov byte [editor_modified], 1
    
    ; insert new line below
    call editor_insert_line_below
    
    ; copy text after cursor to new line
    mov eax, [editor_cursor_y]
    dec eax                         ; the line we were on
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov esi, editor_buffer
    add esi, eax
    add esi, [editor_cursor_x]
    
    mov eax, [editor_cursor_y]      ; new line
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    
    mov ecx, EDITOR_LINE_SIZE
    rep movsb
    
    ; clear rest of previous line
    mov eax, [editor_cursor_y]
    dec eax
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    add edi, [editor_cursor_x]
    
    mov ecx, EDITOR_LINE_SIZE
    sub ecx, [editor_cursor_x]
    mov al, 0
    rep stosb
    
    ; move cursor to start of new line
    mov dword [editor_cursor_x], 0
    
    popa
    ret

editor_insert_line_below:
    pusha
    
    mov byte [editor_modified], 1
    
    ; check if we have space
    mov eax, [editor_line_count]
    cmp eax, EDITOR_MAX_LINES
    jge .done
    
    ; shift all lines below down
    mov eax, [editor_line_count]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov esi, editor_buffer
    add esi, eax
    dec esi
    
    mov edi, esi
    add edi, EDITOR_LINE_SIZE
    
    mov eax, [editor_line_count]
    sub eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov ecx, eax
    
    std
    rep movsb
    cld
    
    ; clear the new line
    mov eax, [editor_cursor_y]
    inc eax
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    
    mov ecx, EDITOR_LINE_SIZE
    xor eax, eax
    rep stosb
    
    inc dword [editor_line_count]
    inc dword [editor_cursor_y]
    mov dword [editor_cursor_x], 0
    
    .done:
    popa
    ret

editor_delete_current_line:
    pusha
    
    mov byte [editor_modified], 1
    
    ; check if last line
    mov eax, [editor_line_count]
    cmp eax, 1
    jle .just_clear
    
    ; shift all lines below up
    mov eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    
    mov esi, edi
    add esi, EDITOR_LINE_SIZE
    
    mov eax, [editor_line_count]
    sub eax, [editor_cursor_y]
    dec eax
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov ecx, eax
    
    rep movsb
    
    dec dword [editor_line_count]
    jmp .done
    
    .just_clear:
    ; just clear the line
    mov eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    
    mov ecx, EDITOR_LINE_SIZE
    xor eax, eax
    rep stosb
    
    .done:
    mov dword [editor_cursor_x], 0
    popa
    ret

editor_insert_tab:
    pusha
    
    mov ecx, EDITOR_TAB_SIZE
    .loop:
        mov al, ' '
        call editor_insert_char
        loop .loop
    
    popa
    ret

; ========================================
; COPY/PASTE
; ========================================

editor_copy_line:
    pusha
    
    ; copy current line to clipboard
    mov eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov esi, editor_buffer
    add esi, eax
    
    mov edi, clipboard_buffer
    mov ecx, EDITOR_LINE_SIZE
    rep movsb
    
    call editor_get_line_length
    mov [clipboard_length], eax
    
    popa
    ret

editor_cut_line:
    pusha
    
    call editor_copy_line
    call editor_delete_current_line
    
    popa
    ret

editor_paste_line:
    pusha
    
    ; insert new line
    call editor_insert_line_below
    
    ; paste clipboard to new line
    mov eax, [editor_cursor_y]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov edi, editor_buffer
    add edi, eax
    
    mov esi, clipboard_buffer
    mov ecx, [clipboard_length]
    rep movsb
    
    popa
    ret

; ========================================
; FILE OPERATIONS
; ========================================

editor_load_file:
    ; ESI = filename
    pusha
    
    ; try to find file in J3KFS
    mov eax, [current_dir_inode]
    mov ebx, esi
    call find_dir_entry
    cmp eax, -1
    je .not_found
    
    ; read file
    mov edi, editor_buffer
    mov ecx, EDITOR_MAX_LINES * EDITOR_LINE_SIZE
    call read_file
    
    ; count lines
    call editor_count_lines
    mov [editor_line_count], eax
    
    jmp .done
    
    .not_found:
    ; new file - start with one blank line
    mov dword [editor_line_count], 1
    mov edi, editor_buffer
    mov ecx, EDITOR_MAX_LINES * EDITOR_LINE_SIZE
    xor eax, eax
    rep stosb
    
    .done:
    mov byte [editor_modified], 0
    popa
    ret

editor_save_file:
    pusha
    
    ; check if we have a filename
    cmp byte [editor_filename], 0
    je .need_filename
    
    ; create or find file
    mov eax, [current_dir_inode]
    mov ebx, editor_filename
    call find_dir_entry
    cmp eax, -1
    jne .file_exists
    
    ; create new file
    mov esi, editor_filename
    call create_file
    
    .file_exists:
    ; calculate file size
    mov eax, [editor_line_count]
    mov ebx, EDITOR_LINE_SIZE
    mul ebx
    mov ecx, eax
    
    ; write file
    mov esi, editor_buffer
    call write_file
    
    mov byte [editor_modified], 0
    
    ; show save message briefly
    mov dword [cursor_x], 0
    mov dword [cursor_y], 24
    mov esi, .saved_msg
    mov ah, 0x70
    .msg_loop:
        lodsb
        test al, al
        jz .done
        call print_char_color
        jmp .msg_loop
    
    .need_filename:
    ; TODO: prompt for filename
    
    .done:
    popa
    ret
    
    .saved_msg: db 'File saved!', 0

editor_count_lines:
    ; count non-empty lines in buffer
    ; returns count in EAX
    pusha
    
    mov esi, editor_buffer
    xor ebx, ebx                ; line count
    
    .line_loop:
        cmp ebx, EDITOR_MAX_LINES
        jge .done
        
        ; check if line is empty
        xor ecx, ecx
        .char_loop:
            lodsb
            test al, al
            jz .line_empty
            cmp al, 32
            jl .line_empty
            inc ecx
            cmp ecx, EDITOR_LINE_SIZE
            jge .next_line
            jmp .char_loop
        
        .line_empty:
        ; skip rest of line
        add esi, EDITOR_LINE_SIZE
        sub esi, ecx
        
        ; if we found any content, this is a line
        test ecx, ecx
        jz .check_more
        
        .next_line:
        inc ebx
        jmp .line_loop
        
        .check_more:
        ; if no more content, we're done
        mov edi, esi
        mov ecx, (EDITOR_MAX_LINES * EDITOR_LINE_SIZE)
        mov eax, ebx
        mov edx, EDITOR_LINE_SIZE
        mul edx
        sub ecx, eax
        xor eax, eax
        repe scasb
        jne .next_line
        jmp .done
    
    .done:
    ; ensure at least 1 line
    test ebx, ebx
    jnz .not_zero
    inc ebx
    .not_zero:
    
    mov [esp + 28], ebx
    popa
    ret

editor_show_save_prompt:
    ; returns EAX = 1 to save, 0 to discard
    pusha
    
    mov dword [cursor_x], 0
    mov dword [cursor_y], 24
    mov esi, .prompt_text
    mov ah, 0x70
    .loop:
        lodsb
        test al, al
        jz .wait_key
        call print_char_color
        jmp .loop
    
    .wait_key:
    call getchar_wait
    cmp al, 'y'
    je .yes
    cmp al, 'Y'
    je .yes
    
    mov dword [esp + 28], 0     ; return 0
    popa
    ret
    
    .yes:
    mov dword [esp + 28], 1     ; return 1
    popa
    ret
    
    .prompt_text: db 'Save changes? (y/n) ', 0

editor_detect_syntax:
    ; ESI = filename
    ; detect syntax mode from extension
    pusha
    
    mov byte [editor_syntax_mode], 0
    
    ; find last dot
    mov edi, esi
    .find_dot:
        lodsb
        test al, al
        jz .check_ext
        cmp al, '.'
        jne .find_dot
        mov edi, esi
        jmp .find_dot
    
    .check_ext:
    ; check for .asm
    mov esi, edi
    mov edi, .ext_asm
    call strcmp
    test eax, eax
    jnz .not_asm
    mov byte [editor_syntax_mode], 1
    jmp .done
    .not_asm:
    
    ; check for .c
    mov esi, edi
    mov edi, .ext_c
    call strcmp
    test eax, eax
    jnz .done
    mov byte [editor_syntax_mode], 2
    
    .done:
    popa
    ret
    
    .ext_asm: db 'asm', 0
    .ext_c: db 'c', 0

; helper to print colored character
print_char_color:
    ; AL = character, AH = color
    pusha
    
    mov ebx, 0xB8000
    mov ecx, [cursor_y]
    imul ecx, 80
    add ecx, [cursor_x]
    shl ecx, 1
    add ebx, ecx
    
    mov [ebx], ax
    inc dword [cursor_x]
    
    popa
    ret
