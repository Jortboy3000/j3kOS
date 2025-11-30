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

; init PS/2 mouse
init_mouse:
    pusha
    
    ; enable mouse (send 0xA8 to port 0x64)
    mov al, 0xA8
    out 0x64, al
    
    ; wait a bit
    mov ecx, 10000
    .wait1:
        nop
        loop .wait1
    
    ; get mouse data (send 0xD4 then 0xF4)
    mov al, 0xD4
    out 0x64, al
    
    mov ecx, 10000
    .wait2:
        nop
        loop .wait2
    
    mov al, 0xF4
    out 0x60, al
    
    ; mouse is ready baby
    mov byte [mouse_initialized], 1
    
    popa
    ret

; update mouse position (call this from IRQ12 handler)
; packet format: byte1=flags, byte2=dx, byte3=dy
mouse_update:
    pusha
    
    ; read mouse data from port 0x60
    in al, 0x60
    mov [.packet], al
    
    ; wait for dx
    mov ecx, 1000
    .wait1:
        in al, 0x64
        test al, 1
        jnz .got_dx
        loop .wait1
    jmp .done
    
    .got_dx:
    in al, 0x60
    mov [.dx], al
    
    ; wait for dy
    mov ecx, 1000
    .wait2:
        in al, 0x64
        test al, 1
        jnz .got_dy
        loop .wait2
    jmp .done
    
    .got_dy:
    in al, 0x60
    mov [.dy], al
    
    ; update buttons
    mov al, [.packet]
    and al, 0x07        ; mask button bits
    mov [mouse_buttons], al
    
    ; update x position
    movsx eax, byte [.dx]
    add [mouse_x], eax
    
    ; clamp x to screen bounds
    mov eax, [mouse_x]
    cmp eax, 0
    jge .x_not_neg
    mov dword [mouse_x], 0
    .x_not_neg:
    cmp eax, VGA_WIDTH
    jl .x_not_big
    mov eax, VGA_WIDTH
    dec eax
    mov [mouse_x], eax
    .x_not_big:
    
    ; update y position (note: dy is inverted)
    movsx eax, byte [.dy]
    neg eax             ; flip sign
    add [mouse_y], eax
    
    ; clamp y
    mov eax, [mouse_y]
    cmp eax, 0
    jge .y_not_neg
    mov dword [mouse_y], 0
    .y_not_neg:
    cmp eax, VGA_HEIGHT
    jl .y_not_big
    mov eax, VGA_HEIGHT
    dec eax
    mov [mouse_y], eax
    .y_not_big:
    
    .done:
    popa
    ret
    
    .packet: db 0
    .dx: db 0
    .dy: db 0

; draw mouse cursor (simple arrow)
draw_mouse_cursor:
    pusha
    
    ; draw a simple cross cursor
    mov eax, [mouse_x]
    mov ebx, [mouse_y]
    
    ; horizontal line
    push eax
    dec eax
    dec eax
    mov ecx, eax
    add ecx, 4
    mov dl, COLOR_WHITE
    call draw_hline
    pop eax
    
    ; vertical line
    push ebx
    dec ebx
    dec ebx
    mov ecx, ebx
    add ecx, 4
    mov dl, COLOR_WHITE
    call draw_vline
    pop ebx
    
    popa
    ret

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
        
        mov byte [esi + 0], BUTTON_PRESSED
        jmp .next
        
        .hover:
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
    
    ; create main window
    mov eax, 40
    mov ebx, 30
    mov ecx, 240
    mov edx, 140
    mov esi, gui_demo_title
    call create_window
    
    ; create buttons
    mov eax, 60
    mov ebx, 60
    mov ecx, 60
    mov edx, 20
    mov esi, gui_button1_label
    mov edi, 0      ; no callback yet
    call create_button
    
    mov eax, 140
    mov ebx, 60
    mov ecx, 60
    mov edx, 20
    mov esi, gui_button2_label
    mov edi, 0
    call create_button
    
    mov eax, 60
    mov ebx, 100
    mov ecx, 140
    mov edx, 20
    mov esi, gui_button3_label
    mov edi, 0
    call create_button
    
    ; main loop (for now just draw once)
    .loop:
        ; clear screen
        mov al, COLOR_DARK_GRAY
        call clear_graphics_screen
        
        ; draw all windows
        xor eax, eax
        .draw_windows:
            cmp eax, [gui_window_count]
            jge .windows_done
            push eax
            call draw_window
            pop eax
            inc eax
            jmp .draw_windows
        
        .windows_done:
        
        ; update and draw buttons
        call update_buttons
        
        xor eax, eax
        .draw_buttons:
            cmp eax, [gui_button_count]
            jge .buttons_done
            push eax
            call draw_button
            pop eax
            inc eax
            jmp .draw_buttons
        
        .buttons_done:
        
        ; draw mouse cursor
        call draw_mouse_cursor
        
        ; small delay
        mov ecx, 100000
        .delay:
            nop
            loop .delay
        
        ; check for keypress to exit (for now)
        ; in real implementation this would be event-driven
        jmp .loop
    
    popa
    ret

gui_demo_title:         db 'j3kOS Window', 0
gui_button1_label:      db 'Button 1', 0
gui_button2_label:      db 'Button 2', 0
gui_button3_label:      db 'Big Button', 0
