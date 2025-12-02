; =====================================================
; GUI FRAMEWORK - WINDOWS, BUTTONS, MOUSE N SHIT
; making this OS actually usable
; =====================================================

; GUI constants
GUI_MAX_WINDOWS     equ 8
GUI_MAX_BUTTONS     equ 16
GUI_WINDOW_SIZE     equ 32      ; bytes per window struct
GUI_BUTTON_SIZE     equ 24      ; bytes per button struct

; window states
WINDOW_HIDDEN       equ 0
WINDOW_VISIBLE      equ 1
WINDOW_FOCUSED      equ 2

; button states
BUTTON_NORMAL       equ 0
BUTTON_HOVER        equ 1
BUTTON_PRESSED      equ 2

; colors for GUI elements
GUI_WINDOW_BG       equ 7       ; light gray
GUI_WINDOW_BORDER   equ 8       ; dark gray
GUI_WINDOW_TITLE    equ 1       ; blue
GUI_BUTTON_BG       equ 7       ; light gray
GUI_BUTTON_HOVER    equ 9       ; light blue
GUI_BUTTON_PRESSED  equ 1       ; dark blue
GUI_BUTTON_BORDER   equ 0       ; black
GUI_TEXT_COLOR      equ 0       ; black

; ========================================
; MOUSE DRIVER (PS/2)
; ========================================

mouse_x:            dd 160      ; current mouse position
mouse_y:            dd 100
mouse_buttons:      db 0        ; bit 0=left, 1=right, 2=middle
mouse_initialized:  db 0
mouse_cycle:        db 0        ; 0, 1, 2
mouse_byte0:        db 0
mouse_byte1:        db 0
mouse_byte2:        db 0

; init PS/2 mouse
init_mouse:
    pusha
    
    ; 1. Disable Keyboard (Port 0x64, Cmd 0xAD)
    call mouse_wait
    mov al, 0xAD
    out 0x64, al
    
    ; 2. Disable Mouse (Port 0x64, Cmd 0xA7)
    call mouse_wait
    mov al, 0xA7
    out 0x64, al
    
    ; 3. Flush Output Buffer
    call mouse_flush
    
    ; 4. Get Compaq Status Byte (Cmd 0x20)
    call mouse_wait
    mov al, 0x20
    out 0x64, al
    call mouse_wait_read
    in al, 0x60
    mov bl, al          ; Save status byte
    
    ; 5. Set Bit 1 (IRQ12) and Clear Bit 5 (Disable Mouse Clock)
    or bl, 2
    and bl, 0xDF
    
    ; 6. Set Compaq Status Byte (Cmd 0x60)
    call mouse_wait
    mov al, 0x60
    out 0x64, al
    call mouse_wait
    mov al, bl
    out 0x60, al
    
    ; 7. Enable Mouse (Cmd 0xA8)
    call mouse_wait
    mov al, 0xA8
    out 0x64, al
    
    ; 8. Reset Mouse (Write 0xFF to 0x60 via 0xD4)
    call mouse_write
    mov al, 0xFF
    out 0x60, al
    call mouse_read_ack ; Expect 0xFA
    call mouse_read_ack ; Expect 0xAA (Self-test)
    call mouse_read_ack ; Expect 0x00 (ID)
    
    ; 9. Enable Streaming (Write 0xF4 to 0x60 via 0xD4)
    call mouse_write
    mov al, 0xF4
    out 0x60, al
    call mouse_read_ack ; Expect 0xFA
    
    ; 10. Enable Keyboard (Cmd 0xAE)
    call mouse_wait
    mov al, 0xAE
    out 0x64, al
    
    ; mouse is ready baby
    mov byte [mouse_initialized], 1
    mov byte [mouse_cycle], 0
    
    popa
    ret

; wait for input buffer to be clear (so we can write)
mouse_wait:
    push ecx
    push ax
    mov ecx, 100000
    .loop:
        in al, 0x64
        test al, 2
        jz .done
        loop .loop
    .done:
    pop ax
    pop ecx
    ret

; wait for output buffer to have data (so we can read)
mouse_wait_read:
    push ecx
    push ax
    mov ecx, 100000
    .loop:
        in al, 0x64
        test al, 1
        jnz .done
        loop .loop
    .done:
    pop ax
    pop ecx
    ret

; flush output buffer
mouse_flush:
    push ax
    .loop:
        in al, 0x64
        test al, 1
        jz .done
        in al, 0x60
        jmp .loop
    .done:
    pop ax
    ret

; prepare to write to mouse (0xD4)
mouse_write:
    call mouse_wait
    mov al, 0xD4
    out 0x64, al
    call mouse_wait
    ret

; read acknowledge byte (0xFA)
mouse_read_ack:
    call mouse_wait_read
    in al, 0x60
    ret

; update mouse position (call this from IRQ12 handler)
; packet format: byte1=flags, byte2=dx, byte3=dy
mouse_update:
    pusha
    
    ; check status register
    in al, 0x64
    test al, 0x01       ; Output buffer full?
    jz .done
    test al, 0x20       ; Mouse data? (Bit 5)
    jz .not_mouse
    
    ; read mouse data from port 0x60
    in al, 0x60
    mov bl, al          ; save byte
    
    ; State Machine
    movzx ecx, byte [mouse_cycle]
    
    cmp ecx, 0
    je .cycle0
    cmp ecx, 1
    je .cycle1
    cmp ecx, 2
    je .cycle2
    jmp .reset_cycle
    
    .cycle0:
        ; Byte 0: Flags
        test bl, 0x08       ; Bit 3 must be 1
        jz .reset_cycle     ; sync error
        
        test bl, 0xC0       ; Check X/Y overflow (Bits 6,7)
        jnz .reset_cycle    ; If overflow, discard packet
        
        mov [mouse_byte0], bl
        inc byte [mouse_cycle]
        jmp .done
        
    .cycle1:
        ; Byte 1: DX
        mov [mouse_byte1], bl
        inc byte [mouse_cycle]
        jmp .done
        
    .cycle2:
        ; Byte 2: DY
        mov [mouse_byte2], bl
        mov byte [mouse_cycle], 0
        
        ; Process full packet
        call process_mouse_packet
        jmp .done
        
    .reset_cycle:
        mov byte [mouse_cycle], 0
        jmp .done
        
    .not_mouse:
        ; Not mouse data, ignore
        jmp .done
    
    .done:
    popa
    ret

process_mouse_packet:
    pusha
    
    ; update buttons
    mov al, [mouse_byte0]
    and al, 0x07        ; mask button bits
    mov [mouse_buttons], al
    
    ; update x position
    movsx eax, byte [mouse_byte1]
    add [mouse_x], eax
    
    ; clamp x to screen bounds
    mov eax, [mouse_x]
    cmp eax, 0
    jge .x_not_neg
    mov dword [mouse_x], 0
    .x_not_neg:
    cmp eax, GFX_WIDTH
    jl .x_not_big
    mov eax, GFX_WIDTH
    dec eax
    mov [mouse_x], eax
    .x_not_big:
    
    ; update y position (note: dy is inverted)
    movsx eax, byte [mouse_byte2]
    neg eax             ; flip sign
    add [mouse_y], eax
    
    ; clamp y
    mov eax, [mouse_y]
    cmp eax, 0
    jge .y_not_neg
    mov dword [mouse_y], 0
    .y_not_neg:
    cmp eax, GFX_HEIGHT
    jl .y_not_big
    mov eax, GFX_HEIGHT
    dec eax
    mov [mouse_y], eax
    .y_not_big:
    
    popa
    ret

; draw mouse cursor (simple arrow)
draw_mouse_cursor:
    pusha
    
    ; draw arrow cursor sprite (11x16)
    mov esi, sprite_arrow_cursor
    movzx eax, word [mouse_x]
    movzx ebx, word [mouse_y]
    mov ecx, 11
    mov edx, 16
    push 0              ; transparent color = 0 (black)
    call draw_sprite
    add esp, 4
    
    popa
    ret

; ========================================
; GUI SPRITES
; ========================================

; arrow cursor sprite (11x16)
sprite_arrow_cursor:
    db 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 15, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0
    db 15, 7, 15, 0, 0, 0, 0, 0, 0, 0, 0
    db 15, 7, 7, 15, 0, 0, 0, 0, 0, 0, 0
    db 15, 7, 7, 7, 15, 0, 0, 0, 0, 0, 0
    db 15, 7, 7, 7, 7, 15, 0, 0, 0, 0, 0
    db 15, 7, 7, 7, 7, 7, 15, 0, 0, 0, 0
    db 15, 7, 7, 7, 7, 7, 7, 15, 0, 0, 0
    db 15, 7, 7, 7, 7, 7, 7, 7, 15, 0, 0
    db 15, 7, 7, 7, 7, 7, 15, 15, 15, 15, 0
    db 15, 7, 7, 15, 7, 7, 15, 0, 0, 0, 0
    db 15, 7, 15, 0, 15, 7, 7, 15, 0, 0, 0
    db 15, 15, 0, 0, 15, 7, 7, 15, 0, 0, 0
    db 15, 0, 0, 0, 0, 15, 7, 7, 15, 0, 0
    db 0, 0, 0, 0, 0, 15, 7, 7, 15, 0, 0
    db 0, 0, 0, 0, 0, 0, 15, 15, 0, 0, 0

; ========================================
; WINDOW MANAGEMENT
; ========================================

; window structure (32 bytes):
; +0: state (1 byte)
; +1: x (2 bytes)
; +3: y (2 bytes)
; +5: width (2 bytes)
; +7: height (2 bytes)
; +9: title pointer (4 bytes)
; +13: padding (19 bytes)

gui_windows:        times (GUI_MAX_WINDOWS * GUI_WINDOW_SIZE) db 0
gui_window_count:   dd 0
gui_focused_window: dd 0

; create a window
; EAX = x
; EBX = y
; ECX = width
; EDX = height
; ESI = title string pointer
; returns: EAX = window index (or -1 if full)
create_window:
    pusha
    
    ; check if we have space
    mov eax, [gui_window_count]
    cmp eax, GUI_MAX_WINDOWS
    jge .full
    
    ; calculate window offset
    mov ebx, GUI_WINDOW_SIZE
    mul ebx
    mov edi, gui_windows
    add edi, eax
    
    ; fill in window data
    mov byte [edi + 0], WINDOW_VISIBLE
    
    mov eax, [esp + 28]     ; x from pusha
    mov [edi + 1], ax
    
    mov eax, [esp + 20]     ; y from pusha
    mov [edi + 3], ax
    
    mov eax, [esp + 16]     ; width from pusha
    mov [edi + 5], ax
    
    mov eax, [esp + 12]     ; height from pusha
    mov [edi + 7], ax
    
    mov eax, [esp + 4]      ; title from pusha
    mov [edi + 9], eax
    
    ; increment count
    mov eax, [gui_window_count]
    mov [.result], eax
    inc dword [gui_window_count]
    
    popa
    mov eax, [.result]
    ret
    
    .full:
    popa
    mov eax, -1
    ret
    
    .result: dd 0

; draw a window
; EAX = window index
draw_window:
    pusha
    
    ; get window pointer
    mov ebx, GUI_WINDOW_SIZE
    mul ebx
    mov esi, gui_windows
    add esi, eax
    
    ; check if visible
    mov al, [esi + 0]
    cmp al, WINDOW_HIDDEN
    je .done
    
    ; get window coords
    movzx eax, word [esi + 1]       ; x
    movzx ebx, word [esi + 3]       ; y
    movzx ecx, word [esi + 5]       ; width
    movzx edx, word [esi + 7]       ; height
    
    mov [.x], eax
    mov [.y], ebx
    mov [.width], ecx
    mov [.height], edx
    
    ; draw title bar (10 pixels high)
    mov eax, [.x]
    mov ebx, [.y]
    mov ecx, [.x]
    add ecx, [.width]
    dec ecx
    mov edx, [.y]
    add edx, 10
    push GUI_WINDOW_TITLE
    call draw_filled_rect
    add esp, 4
    
    ; draw window body
    mov eax, [.x]
    mov ebx, [.y]
    add ebx, 11
    mov ecx, [.x]
    add ecx, [.width]
    dec ecx
    mov edx, [.y]
    add edx, [.height]
    dec edx
    push GUI_WINDOW_BG
    call draw_filled_rect
    add esp, 4
    
    ; draw border
    mov eax, [.x]
    mov ebx, [.y]
    mov ecx, [.x]
    add ecx, [.width]
    dec ecx
    mov edx, [.y]
    add edx, [.height]
    dec edx
    push GUI_WINDOW_BORDER
    call draw_rect
    add esp, 4
    
    ; draw title bar bottom line
    mov eax, [.x]
    mov ebx, [.y]
    add ebx, 10
    mov ecx, [.x]
    add ecx, [.width]
    dec ecx
    mov dl, GUI_WINDOW_BORDER
    call draw_hline
    
    ; TODO: draw title text when we have font rendering
    
    .done:
    popa
    ret
    
    .x: dd 0
    .y: dd 0
    .width: dd 0
    .height: dd 0

; ========================================
; BUTTON MANAGEMENT
; ========================================

; button structure (24 bytes):
; +0: state (1 byte)
; +1: x (2 bytes)
; +3: y (2 bytes)
; +5: width (2 bytes)
; +7: height (2 bytes)
; +9: label pointer (4 bytes)
; +13: callback pointer (4 bytes)
; +17: padding (7 bytes)

gui_buttons:        times (GUI_MAX_BUTTONS * GUI_BUTTON_SIZE) db 0
gui_button_count:   dd 0

; create a button
; EAX = x
; EBX = y
; ECX = width
; EDX = height
; ESI = label string pointer
; EDI = callback function pointer
; returns: EAX = button index (or -1 if full)
create_button:
    pusha
    
    mov eax, [gui_button_count]
    cmp eax, GUI_MAX_BUTTONS
    jge .full
    
    ; calculate button offset
    mov ebx, GUI_BUTTON_SIZE
    mul ebx
    mov edi, gui_buttons
    add edi, eax
    
    ; fill button data
    mov byte [edi + 0], BUTTON_NORMAL
    
    mov eax, [esp + 28]     ; x
    mov [edi + 1], ax
    
    mov eax, [esp + 20]     ; y
    mov [edi + 3], ax
    
    mov eax, [esp + 16]     ; width
    mov [edi + 5], ax
    
    mov eax, [esp + 12]     ; height
    mov [edi + 7], ax
    
    mov eax, [esp + 4]      ; label
    mov [edi + 9], eax
    
    mov eax, [esp + 0]      ; callback
    mov [edi + 13], eax
    
    mov eax, [gui_button_count]
    mov [.result], eax
    inc dword [gui_button_count]
    
    popa
    mov eax, [.result]
    ret
    
    .full:
    popa
    mov eax, -1
    ret
    
    .result: dd 0

; draw a button
; EAX = button index
draw_button:
    pusha
    
    ; get button pointer
    mov ebx, GUI_BUTTON_SIZE
    mul ebx
    mov esi, gui_buttons
    add esi, eax
    
    ; get button coords
    movzx eax, word [esi + 1]
    movzx ebx, word [esi + 3]
    movzx ecx, word [esi + 5]
    movzx edx, word [esi + 7]
    
    mov [.x], eax
    mov [.y], ebx
    mov [.width], ecx
    mov [.height], edx
    
    ; get button state
    mov al, [esi + 0]
    mov [.state], al
    
    ; choose color based on state
    mov al, GUI_BUTTON_BG
    cmp byte [.state], BUTTON_HOVER
    jne .not_hover
    mov al, GUI_BUTTON_HOVER
    .not_hover:
    cmp byte [.state], BUTTON_PRESSED
    jne .not_pressed
    mov al, GUI_BUTTON_PRESSED
    .not_pressed:
    mov [.color], al
    
    ; draw filled button
    mov eax, [.x]
    mov ebx, [.y]
    mov ecx, [.x]
    add ecx, [.width]
    dec ecx
    mov edx, [.y]
    add edx, [.height]
    dec edx
    movzx edi, byte [.color]
    push edi
    call draw_filled_rect
    add esp, 4
    
    ; draw border
    mov eax, [.x]
    mov ebx, [.y]
    mov ecx, [.x]
    add ecx, [.width]
    dec ecx
    mov edx, [.y]
    add edx, [.height]
    dec edx
    push GUI_BUTTON_BORDER
    call draw_rect
    add esp, 4
    
    ; TODO: draw label text
    
    popa
    ret
    
    .x: dd 0
    .y: dd 0
    .width: dd 0
    .height: dd 0
    .state: db 0
    .color: db 0

; update button states based on mouse position
update_buttons:
    pusha
    
    mov ecx, [gui_button_count]
    test ecx, ecx
    jz .done
    
    mov edi, 0      ; button index
    
    .loop:
        cmp edi, ecx
        jge .done
        
        ; get button pointer
        mov eax, edi
        mov ebx, GUI_BUTTON_SIZE
        mul ebx
        mov esi, gui_buttons
        add esi, eax
        
        ; get button bounds
        movzx eax, word [esi + 1]       ; x
        movzx ebx, word [esi + 3]       ; y
        movzx edx, word [esi + 5]       ; width
        add edx, eax                    ; x + width
        push edx
        movzx edx, word [esi + 7]       ; height
        add edx, ebx                    ; y + height
        
        ; check if mouse is over button
        mov edx, [mouse_x]
        cmp edx, eax
        jl .not_over
        pop eax                         ; x + width
        cmp edx, eax
        jge .not_over
        
        mov edx, [mouse_y]
        cmp edx, ebx
        jl .not_over
        mov eax, [esp - 4]              ; y + height (still on stack conceptually)
        cmp edx, eax
        jge .not_over
        
        ; mouse is over this button!
        ; check if left button pressed
        test byte [mouse_buttons], 1
        jz .hover
        
        ; button is pressed - check if it was released (click event)
        cmp byte [esi + 0], BUTTON_PRESSED
        je .already_pressed
        
        ; just pressed
        mov byte [esi + 0], BUTTON_PRESSED
        jmp .next
        
        .already_pressed:
        ; still pressed, keep state
        jmp .next
        
        .hover:
        ; mouse over but not pressed
        ; check if button was just released (trigger callback)
        cmp byte [esi + 0], BUTTON_PRESSED
        jne .set_hover
        
        ; button was pressed and now released = CLICK!
        ; call the callback if it exists
        mov eax, [esi + 13]     ; callback pointer
        test eax, eax
        jz .set_hover
        
        ; save registers and call
        push esi
        push edi
        push ecx
        call eax
        pop ecx
        pop edi
        pop esi
        
        .set_hover:
        mov byte [esi + 0], BUTTON_HOVER
        jmp .next
        
        .not_over:
        ; clean stack if we jumped here
        mov eax, esp
        and eax, 3
        test eax, eax
        jz .stack_ok
        pop eax
        .stack_ok:
        
        mov byte [esi + 0], BUTTON_NORMAL
        
        .next:
        inc edi
        jmp .loop
    
    .done:
    popa
    ret

; ========================================
; GUI DEMO
; ========================================

; show a demo GUI
gui_demo:
    pusha
    
    ; Switch to graphics mode (320x200x256)
    call set_graphics_mode
    
    ; initialize mouse
    call init_mouse
    
    ; reset GUI state
    mov byte [gui_exit_flag], 0
    mov dword [gui_window_count], 0
    mov dword [gui_button_count], 0
    
    ; create main window
    mov eax, 40
    mov ebx, 30
    mov ecx, 240
    mov edx, 140
    mov esi, gui_demo_title
    call create_window
    
    ; create buttons
    ; Button 1
    mov eax, 60
    mov ebx, 60
    mov ecx, 80
    mov edx, 20
    mov esi, gui_button1_label
    mov edi, gui_button1_callback
    call create_button
    
    ; Button 2
    mov eax, 160
    mov ebx, 60
    mov ecx, 80
    mov edx, 20
    mov esi, gui_button2_label
    mov edi, gui_button2_callback
    call create_button
    
    ; Exit Button
    mov eax, 110
    mov ebx, 100
    mov ecx, 100
    mov edx, 20
    mov esi, gui_button3_label
    mov edi, gui_button3_callback
    call create_button
    
    ; MAIN GUI LOOP
    .loop:
        ; check exit flag
        cmp byte [gui_exit_flag], 1
        je .exit

        ; 1. Clear screen (or redraw background)
        ; For less flicker, we should only redraw what changed, but for now
        ; we'll just clear to a solid color to be safe.
        mov al, 3           ; Cyan background
        call clear_graphics_screen
        
        ; 2. Update Mouse (Handled by IRQ12 now)
        ; call mouse_update
        
        ; 3. Update Logic (Buttons)
        call update_buttons
        
        ; 4. Draw Windows
        ; (We only have one for now)
        mov eax, 0
        call draw_window
        
        ; 5. Draw Buttons
        mov ecx, [gui_button_count]
        xor eax, eax
        .draw_btns:
            cmp eax, ecx
            jge .btns_done
            push eax
            push ecx
            call draw_button
            pop ecx
            pop eax
            inc eax
            jmp .draw_btns
        .btns_done:
        
        ; 6. Draw Status Text
        mov esi, gui_status_msg
        mov eax, 50
        mov ebx, 150
        mov dl, 15              ; white
        call draw_string_gfx
        
        ; 7. Draw Mouse Cursor (Last!)
        call draw_mouse_cursor
        
        ; 8. Check for Exit Key (ESC)
        in al, 0x64
        test al, 1
        jz .no_key
        in al, 0x60
        cmp al, 0x01        ; ESC
        je .exit
        .no_key:
        
        ; 9. VSync / Delay
        ; Wait for retrace to reduce flicker
        mov dx, 0x3DA
        .wait_retrace:
            in al, dx
            test al, 8
            jz .wait_retrace
            
        jmp .loop
    
    .exit:
    ; Switch back to text mode
    call set_text_mode
    
    popa
    ret

; button callbacks
gui_button1_callback:
    pusha
    ; change status message
    mov esi, .msg
    mov edi, gui_status_msg
    mov ecx, 20
    rep movsb
    popa
    ret
    .msg: db 'Button 1 clicked!  ', 0

gui_button2_callback:
    pusha
    mov esi, .msg
    mov edi, gui_status_msg
    mov ecx, 20
    rep movsb
    popa
    ret
    .msg: db 'Button 2 clicked!  ', 0

gui_button3_callback:
    pusha
    mov byte [gui_exit_flag], 1
    popa
    ret

gui_exit_flag: db 0

gui_demo_title:         db 'j3kOS Window', 0
gui_button1_label:      db 'Button 1', 0
gui_button2_label:      db 'Button 2', 0
gui_button3_label:      db 'Exit to Text', 0
gui_status_msg:         db 'Click a button...  ', 0

; IRQ12 Handler - Mouse
irq12_handler:
    pusha
    
    call mouse_update
    
    ; Send EOI to PIC (slave)
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    
    popa
    iret
