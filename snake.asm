; =====================================================
; SNAKE GAME FOR J3KOS
; The classic game, Western Sydney Edition
; =====================================================

; Game Constants
SNAKE_BLOCK_SIZE    equ 10      ; 10x10 pixels
SNAKE_GRID_W        equ 32      ; 320 / 10
SNAKE_GRID_H        equ 20      ; 200 / 10
SNAKE_MAX_LEN       equ 256     ; Max snake length

; Colors
COLOR_SNAKE_HEAD    equ 2       ; Green
COLOR_SNAKE_BODY    equ 10      ; Light Green
COLOR_FOOD          equ 4       ; Red
COLOR_BG            equ 0       ; Black
COLOR_TEXT          equ 15      ; White

; Game Variables
snake_x:            times SNAKE_MAX_LEN db 0
snake_y:            times SNAKE_MAX_LEN db 0
snake_len:          dd 0
snake_dir:          db 0        ; 0=Right, 1=Down, 2=Left, 3=Up
snake_score:        dd 0
food_x:             db 0
food_y:             db 0
game_over:          db 0
rand_seed:          dd 123456789

msg_snake_start:    db "Starting Snake Game... Press any key to enter graphics mode.", 10, 0

; ========================================
; MAIN GAME LOOP
; ========================================
snake_game:
    pusha
    
    ; Initialize graphics
    call set_graphics_mode
    
    ; Initialize game state
    call snake_init
    
    .game_loop:
        ; 1. Clear Screen (or just the play area)
        mov al, COLOR_BG
        call clear_graphics_screen
        
        ; 3. Handle Input
        call snake_input
        
        ; 4. Update Game Logic
        call snake_update
        
        ; Check Game Over
        cmp byte [game_over], 1
        je .do_game_over
        
        ; 5. Draw Everything
        call snake_draw
        
        ; 6. Delay (Game Speed)
        mov ecx, 60000000    ; Slower speed (approx 20x slower than before)
        .delay:
            nop
            loop .delay
            
        jmp .game_loop
        
    .do_game_over:
        ; Show Game Over Screen
        mov esi, msg_game_over
        mov eax, 110
        mov ebx, 90
        mov dl, 4           ; Red
        call draw_string_gfx
        
        mov esi, msg_score_prefix
        mov eax, 120
        mov ebx, 105
        mov dl, 15          ; White
        call draw_string_gfx
        
        ; Draw "Press ESC" message
        mov esi, msg_press_esc
        mov eax, 100
        mov ebx, 120
        mov dl, 14          ; Yellow
        call draw_string_gfx
        
        ; Clear keyboard buffer before waiting
        .drain_buffer:
            call getchar
            test al, al
            jnz .drain_buffer
            
        ; Wait for ESC to exit
        .wait_exit:
            call getchar
            cmp al, 27      ; ESC
            jne .wait_exit
        
        ; Exit
        call set_text_mode
        call clear_screen
        popa
        ret

msg_press_esc:      db "Press ESC to exit", 0

; ========================================
; INITIALIZATION
; ========================================
snake_init:
    pusha
    
    ; Reset variables
    mov dword [snake_len], 3
    mov byte [snake_dir], 0     ; Right
    mov dword [snake_score], 0
    mov byte [game_over], 0
    
    ; Init snake position (center)
    mov byte [snake_x], 16      ; Head
    mov byte [snake_y], 10
    mov byte [snake_x + 1], 15  ; Body
    mov byte [snake_y + 1], 10
    mov byte [snake_x + 2], 14  ; Tail
    mov byte [snake_y + 2], 10
    
    ; Seed RNG with TSC
    rdtsc
    mov [rand_seed], eax
    
    ; Spawn first food
    call snake_spawn_food
    
    popa
    ret

; ========================================
; INPUT HANDLING
; ========================================
snake_input:
    pusha
    
    ; Check for keypress (non-blocking)
    call getchar
    test al, al
    jz .done
    
    ; Handle Keys (using kernel mapped codes)
    ; Up: 1, Left: 2, Right: 3, Down: 4
    ; ESC: 27
    
    cmp al, 27      ; ESC
    je .exit_game
    
    cmp al, 1       ; Up
    je .go_up
    cmp al, 4       ; Down
    je .go_down
    cmp al, 2       ; Left
    je .go_left
    cmp al, 3       ; Right
    je .go_right
    jmp .done
    
    .go_up:
        cmp byte [snake_dir], 1     ; Can't go up if going down
        je .done
        mov byte [snake_dir], 3
        jmp .done
    .go_down:
        cmp byte [snake_dir], 3     ; Can't go down if going up
        je .done
        mov byte [snake_dir], 1
        jmp .done
    .go_left:
        cmp byte [snake_dir], 0     ; Can't go left if going right
        je .done
        mov byte [snake_dir], 2
        jmp .done
    .go_right:
        cmp byte [snake_dir], 2     ; Can't go right if going left
        je .done
        mov byte [snake_dir], 0
        jmp .done
        
    .exit_game:
        mov byte [game_over], 1
        
    .done:
    popa
    ret

; ========================================
; UPDATE LOGIC
; ========================================
snake_update:
    pusha
    
    ; 1. Move Body (Shift array right)
    mov ecx, [snake_len]
    dec ecx             ; Don't move head yet
    
    ; Point to end of snake
    mov esi, snake_x
    add esi, ecx        ; Last element index
    
    .move_loop:
        test ecx, ecx
        jz .move_head
        
        ; snake_x[i] = snake_x[i-1]
        mov al, [snake_x + ecx - 1]
        mov [snake_x + ecx], al
        
        mov al, [snake_y + ecx - 1]
        mov [snake_y + ecx], al
        
        dec ecx
        jmp .move_loop
        
    .move_head:
    ; 2. Move Head based on direction
    mov al, [snake_x]
    mov bl, [snake_y]
    
    cmp byte [snake_dir], 0 ; Right
    je .move_right
    cmp byte [snake_dir], 1 ; Down
    je .move_down
    cmp byte [snake_dir], 2 ; Left
    je .move_left
    cmp byte [snake_dir], 3 ; Up
    je .move_up
    
    .move_right:
        inc al
        jmp .check_collision
    .move_down:
        inc bl
        jmp .check_collision
    .move_left:
        dec al
        jmp .check_collision
    .move_up:
        dec bl
        jmp .check_collision
        
    .check_collision:
    ; 3. Wall Collision
    cmp al, 0
    jl .collision
    cmp al, SNAKE_GRID_W
    jge .collision
    cmp bl, 0
    jl .collision
    cmp bl, SNAKE_GRID_H
    jge .collision
    
    ; 4. Self Collision
    mov ecx, [snake_len]
    dec ecx
    mov edi, 1          ; Start checking from body segment 1
    
    .self_check:
        cmp edi, ecx
        jg .no_collision
        
        cmp al, [snake_x + edi]
        jne .next_seg
        cmp bl, [snake_y + edi]
        je .collision
        
        .next_seg:
        inc edi
        jmp .self_check
        
    .no_collision:
    ; Update head position
    mov [snake_x], al
    mov [snake_y], bl
    
    ; 5. Check Food
    cmp al, [food_x]
    jne .done
    cmp bl, [food_y]
    jne .done
    
    ; Ate food!
    call snake_eat
    jmp .done
    
    .collision:
    mov byte [game_over], 1
    
    .done:
    popa
    ret

snake_eat:
    pusha
    
    ; Increase length
    inc dword [snake_len]
    inc dword [snake_score]
    
    ; Play sound
    mov eax, 1000
    mov ebx, 50
    call play_tone
    
    ; Spawn new food
    call snake_spawn_food
    
    popa
    ret

; ========================================
; DRAWING
; ========================================
snake_draw:
    pusha
    
    ; Draw Food
    movzx eax, byte [food_x]
    movzx ebx, byte [food_y]
    call grid_to_screen
    mov ecx, eax
    add ecx, SNAKE_BLOCK_SIZE
    mov edx, ebx
    add edx, SNAKE_BLOCK_SIZE
    push COLOR_FOOD
    call draw_filled_rect
    add esp, 4
    
    ; Draw Snake
    mov ecx, [snake_len]
    xor edi, edi
    
    .draw_loop:
        cmp edi, ecx
        jge .done
        
        movzx eax, byte [snake_x + edi]
        movzx ebx, byte [snake_y + edi]
        call grid_to_screen
        
        ; Save coords for rect
        push eax
        push ebx
        
        mov ecx, eax
        add ecx, SNAKE_BLOCK_SIZE
        dec ecx         ; 1px gap
        mov edx, ebx
        add edx, SNAKE_BLOCK_SIZE
        dec edx         ; 1px gap
        
        pop ebx
        pop eax
        
        ; Color: Head is different
        mov dl, COLOR_SNAKE_BODY
        test edi, edi
        jnz .draw_body
        mov dl, COLOR_SNAKE_HEAD
        .draw_body:
        
        movzx esi, dl
        push esi
        call draw_filled_rect
        add esp, 4
        
        inc edi
        jmp .draw_loop
        
    .done:
    popa
    ret

; Convert grid coords (AL, BL) to screen coords (EAX, EBX)
grid_to_screen:
    movzx eax, al
    mov edx, SNAKE_BLOCK_SIZE
    mul edx
    push eax    ; Save X
    
    movzx eax, bl
    mov edx, SNAKE_BLOCK_SIZE
    mul edx
    mov ebx, eax ; Y
    
    pop eax     ; Restore X
    ret

; ========================================
; UTILITIES
; ========================================
snake_spawn_food:
    pusha
    
    .try_again:
    ; Random X (0 to 31)
    call rand
    and eax, 31
    mov [food_x], al
    
    ; Random Y (0 to 19)
    call rand
    xor edx, edx
    mov ecx, 20
    div ecx
    mov [food_y], dl
    
    ; Check if food spawned on snake
    mov ecx, [snake_len]
    xor edi, edi
    .check_pos:
        cmp edi, ecx
        jge .ok
        
        mov al, [food_x]
        cmp al, [snake_x + edi]
        jne .next
        mov al, [food_y]
        cmp al, [snake_y + edi]
        je .try_again   ; Spawned on body, retry
        
        .next:
        inc edi
        jmp .check_pos
        
    .ok:
    popa
    ret

; Simple LCG Random Number Generator
rand:
    mov eax, [rand_seed]
    mov edx, 1103515245
    mul edx
    add eax, 12345
    mov [rand_seed], eax
    shr eax, 16
    ret

msg_game_over:      db "YA DOGGED IT!", 0
msg_score_prefix:   db "Score: ", 0
