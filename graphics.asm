; =====================================================
; GRAPHICS MODE - VGA MODE 13h (320x200x256)
; time to draw some pixels baby
; =====================================================

; VGA constants (some already defined in kernel32.asm)
; VGA_WIDTH           equ 320
; VGA_HEIGHT          equ 200
VGA_MEMORY          equ 0xA0000
VGA_PIXELS          equ 64000       ; 320 * 200

; current video mode (0 = text, 1 = graphics)
video_mode: db 0

; color palette (some basic colors)
COLOR_BLACK         equ 0
COLOR_BLUE          equ 1
COLOR_GREEN         equ 2
COLOR_CYAN          equ 3
COLOR_RED           equ 4
COLOR_MAGENTA       equ 5
COLOR_BROWN         equ 6
COLOR_LIGHT_GRAY    equ 7
COLOR_DARK_GRAY     equ 8
COLOR_LIGHT_BLUE    equ 9
COLOR_LIGHT_GREEN   equ 10
COLOR_LIGHT_CYAN    equ 11
COLOR_LIGHT_RED     equ 12
COLOR_LIGHT_MAGENTA equ 13
COLOR_YELLOW        equ 14
COLOR_WHITE         equ 15

; ========================================
; MODE SWITCHING
; ========================================

; switch to graphics mode (320x200x256)
set_graphics_mode:
    pusha
    
    ; BIOS int 10h, AH=0, AL=13h
    mov ax, 0x0013
    int 0x10
    
    ; we're in graphics mode now
    mov byte [video_mode], 1
    
    popa
    ret

; go back to text mode
set_text_mode:
    pusha
    
    ; BIOS int 10h, AH=0, AL=3 (80x25 text)
    mov ax, 0x0003
    int 0x10
    
    ; text mode baby
    mov byte [video_mode], 0
    
    popa
    ret

; ========================================
; BASIC DRAWING
; ========================================

; plot a pixel
; EAX = x
; EBX = y
; CL = color
plot_pixel:
    pusha
    
    ; bounds check
    cmp eax, VGA_WIDTH
    jge .done
    cmp ebx, VGA_HEIGHT
    jge .done
    
    ; calculate offset: y * 320 + x
    push eax
    mov eax, ebx
    mov edx, VGA_WIDTH
    mul edx             ; EAX = y * 320
    pop edx
    add eax, edx        ; EAX = y * 320 + x
    
    ; write pixel
    mov edi, VGA_MEMORY
    add edi, eax
    mov [edi], cl
    
    .done:
    popa
    ret

; clear screen with color
; AL = color
clear_graphics_screen:
    pusha
    
    ; fill all 64000 pixels
    mov edi, VGA_MEMORY
    mov ecx, VGA_PIXELS
    rep stosb
    
    popa
    ret

; draw horizontal line
; EAX = x1
; EBX = y
; ECX = x2
; DL = color
draw_hline:
    pusha
    
    ; make sure x1 <= x2
    cmp eax, ecx
    jle .order_ok
    xchg eax, ecx
    
    .order_ok:
    ; bounds check
    cmp ebx, VGA_HEIGHT
    jge .done
    
    ; calculate start offset
    push eax
    mov eax, ebx
    mov edi, VGA_WIDTH
    mul edi
    pop edi
    add eax, edi        ; EAX = y * 320 + x1
    
    ; calculate length
    sub ecx, edi
    inc ecx
    
    ; draw line
    mov edi, VGA_MEMORY
    add edi, eax
    mov al, dl
    rep stosb
    
    .done:
    popa
    ret

; draw vertical line
; EAX = x
; EBX = y1
; ECX = y2
; DL = color
draw_vline:
    pusha
    
    ; make sure y1 <= y2
    cmp ebx, ecx
    jle .order_ok
    xchg ebx, ecx
    
    .order_ok:
    ; bounds check
    cmp eax, VGA_WIDTH
    jge .done
    
    mov esi, ebx        ; y counter
    
    .loop:
        cmp esi, ecx
        jg .done
        
        ; plot pixel at (eax, esi)
        push eax
        push ebx
        push ecx
        mov ebx, esi
        mov cl, dl
        call plot_pixel
        pop ecx
        pop ebx
        pop eax
        
        inc esi
        jmp .loop
    
    .done:
    popa
    ret

; draw rectangle outline
; EAX = x1
; EBX = y1
; ECX = x2
; EDX = y2
; [esp+4] = color (passed on stack)
draw_rect:
    pusha
    
    ; save coords
    mov [.x1], eax
    mov [.y1], ebx
    mov [.x2], ecx
    mov [.y2], edx
    
    ; get color from stack
    mov edi, [esp + 36]     ; 8 pushes + return address
    mov [.color], edi
    
    ; top line
    mov eax, [.x1]
    mov ebx, [.y1]
    mov ecx, [.x2]
    mov dl, byte [.color]
    call draw_hline
    
    ; bottom line
    mov eax, [.x1]
    mov ebx, [.y2]
    mov ecx, [.x2]
    mov dl, byte [.color]
    call draw_hline
    
    ; left line
    mov eax, [.x1]
    mov ebx, [.y1]
    mov ecx, [.y2]
    mov dl, byte [.color]
    call draw_vline
    
    ; right line
    mov eax, [.x2]
    mov ebx, [.y1]
    mov ecx, [.y2]
    mov dl, byte [.color]
    call draw_vline
    
    popa
    ret
    
    .x1: dd 0
    .y1: dd 0
    .x2: dd 0
    .y2: dd 0
    .color: dd 0

; draw filled rectangle
; EAX = x1
; EBX = y1
; ECX = x2
; EDX = y2
; [esp+4] = color
draw_filled_rect:
    pusha
    
    mov [.x1], eax
    mov [.y1], ebx
    mov [.x2], ecx
    mov [.y2], edx
    
    ; get color
    mov edi, [esp + 36]
    mov [.color], edi
    
    ; draw horizontal lines for each y
    mov esi, [.y1]
    
    .loop:
        cmp esi, [.y2]
        jg .done
        
        mov eax, [.x1]
        mov ebx, esi
        mov ecx, [.x2]
        mov dl, byte [.color]
        call draw_hline
        
        inc esi
        jmp .loop
    
    .done:
    popa
    ret
    
    .x1: dd 0
    .y1: dd 0
    .x2: dd 0
    .y2: dd 0
    .color: dd 0

; draw line (Bresenham's algorithm)
; EAX = x1
; EBX = y1
; ECX = x2
; EDX = y2
; [esp+4] = color
draw_line:
    pusha
    
    ; save params
    mov [.x1], eax
    mov [.y1], ebx
    mov [.x2], ecx
    mov [.y2], edx
    mov edi, [esp + 36]
    mov [.color], edi
    
    ; calculate dx and dy
    mov eax, [.x2]
    sub eax, [.x1]
    mov [.dx], eax
    
    mov eax, [.y2]
    sub eax, [.y1]
    mov [.dy], eax
    
    ; absolute values
    mov eax, [.dx]
    test eax, eax
    jns .dx_positive
    neg eax
    .dx_positive:
    mov [.dx_abs], eax
    
    mov eax, [.dy]
    test eax, eax
    jns .dy_positive
    neg eax
    .dy_positive:
    mov [.dy_abs], eax
    
    ; step directions
    mov dword [.sx], 1
    mov eax, [.x1]
    cmp eax, [.x2]
    jl .sx_ok
    mov dword [.sx], -1
    .sx_ok:
    
    mov dword [.sy], 1
    mov eax, [.y1]
    cmp eax, [.y2]
    jl .sy_ok
    mov dword [.sy], -1
    .sy_ok:
    
    ; initial error
    mov eax, [.dx_abs]
    sub eax, [.dy_abs]
    mov [.err], eax
    
    ; current point
    mov eax, [.x1]
    mov [.x], eax
    mov eax, [.y1]
    mov [.y], eax
    
    .loop:
        ; plot current point
        mov eax, [.x]
        mov ebx, [.y]
        mov cl, byte [.color]
        call plot_pixel
        
        ; reached end?
        mov eax, [.x]
        cmp eax, [.x2]
        jne .not_done
        mov eax, [.y]
        cmp eax, [.y2]
        je .done
        
        .not_done:
        ; e2 = 2 * err
        mov eax, [.err]
        add eax, eax
        mov [.e2], eax
        
        ; if e2 > -dy
        mov ebx, [.dy_abs]
        neg ebx
        cmp eax, ebx
        jle .skip_x
        
        mov eax, [.err]
        sub eax, [.dy_abs]
        mov [.err], eax
        mov eax, [.x]
        add eax, [.sx]
        mov [.x], eax
        
        .skip_x:
        ; if e2 < dx
        mov eax, [.e2]
        cmp eax, [.dx_abs]
        jge .skip_y
        
        mov eax, [.err]
        add eax, [.dx_abs]
        mov [.err], eax
        mov eax, [.y]
        add eax, [.sy]
        mov [.y], eax
        
        .skip_y:
        jmp .loop
    
    .done:
    popa
    ret
    
    .x1: dd 0
    .y1: dd 0
    .x2: dd 0
    .y2: dd 0
    .color: dd 0
    .dx: dd 0
    .dy: dd 0
    .dx_abs: dd 0
    .dy_abs: dd 0
    .sx: dd 0
    .sy: dd 0
    .err: dd 0
    .e2: dd 0
    .x: dd 0
    .y: dd 0

; ========================================
; BITMAP / SPRITE RENDERING
; ========================================

; draw a bitmap/sprite
; ESI = pointer to sprite data
; EAX = x position
; EBX = y position
; ECX = width
; EDX = height
; [esp+4] = transparent color (0xFF = no transparency)
draw_sprite:
    pusha
    
    mov [.x], eax
    mov [.y], ebx
    mov [.width], ecx
    mov [.height], edx
    mov [.sprite_ptr], esi
    
    ; get transparent color from stack
    mov edi, [esp + 36]
    mov [.transparent], edi
    
    mov dword [.row], 0
    
    .row_loop:
        mov eax, [.row]
        cmp eax, [.height]
        jge .done
        
        mov dword [.col], 0
        
        .col_loop:
            mov eax, [.col]
            cmp eax, [.width]
            jge .next_row
            
            ; get pixel from sprite data
            mov esi, [.sprite_ptr]
            mov eax, [.row]
            mul dword [.width]
            add eax, [.col]
            add esi, eax
            mov al, [esi]
            
            ; check if transparent
            cmp al, byte [.transparent]
            je .skip_pixel
            
            ; draw the pixel
            push eax
            mov eax, [.x]
            add eax, [.col]
            mov ebx, [.y]
            add ebx, [.row]
            pop ecx
            call plot_pixel
            
            .skip_pixel:
            inc dword [.col]
            jmp .col_loop
        
        .next_row:
        inc dword [.row]
        jmp .row_loop
    
    .done:
    popa
    ret
    
    .x: dd 0
    .y: dd 0
    .width: dd 0
    .height: dd 0
    .sprite_ptr: dd 0
    .transparent: dd 0
    .row: dd 0
    .col: dd 0

; draw a scaled sprite (simple nearest neighbor)
; ESI = pointer to sprite data
; EAX = x position
; EBX = y position
; ECX = width
; EDX = height
; [esp+4] = scale factor (1, 2, 3, etc.)
; [esp+8] = transparent color
draw_sprite_scaled:
    pusha
    
    mov [.x], eax
    mov [.y], ebx
    mov [.width], ecx
    mov [.height], edx
    mov [.sprite_ptr], esi
    
    ; get params from stack
    mov edi, [esp + 36]
    mov [.scale], edi
    mov edi, [esp + 40]
    mov [.transparent], edi
    
    mov dword [.row], 0
    
    .row_loop:
        mov eax, [.row]
        cmp eax, [.height]
        jge .done
        
        mov dword [.col], 0
        
        .col_loop:
            mov eax, [.col]
            cmp eax, [.width]
            jge .next_row
            
            ; get pixel from sprite
            mov esi, [.sprite_ptr]
            mov eax, [.row]
            mul dword [.width]
            add eax, [.col]
            add esi, eax
            mov al, [esi]
            
            ; transparent?
            cmp al, byte [.transparent]
            je .skip_pixel
            
            ; draw scaled pixel (fill scale x scale square)
            mov [.color], al
            mov dword [.sy], 0
            
            .scale_y:
                mov eax, [.sy]
                cmp eax, [.scale]
                jge .skip_pixel
                
                mov dword [.sx], 0
                
                .scale_x:
                    mov eax, [.sx]
                    cmp eax, [.scale]
                    jge .next_scale_y
                    
                    ; calculate screen position
                    mov eax, [.x]
                    mov ebx, [.col]
                    mul dword [.scale]
                    add eax, ebx
                    add eax, [.sx]
                    
                    mov ebx, [.y]
                    push eax
                    mov eax, [.row]
                    mul dword [.scale]
                    add ebx, eax
                    add ebx, [.sy]
                    pop eax
                    
                    mov cl, byte [.color]
                    call plot_pixel
                    
                    inc dword [.sx]
                    jmp .scale_x
                
                .next_scale_y:
                inc dword [.sy]
                jmp .scale_y
            
            .skip_pixel:
            inc dword [.col]
            jmp .col_loop
        
        .next_row:
        inc dword [.row]
        jmp .row_loop
    
    .done:
    popa
    ret
    
    .x: dd 0
    .y: dd 0
    .width: dd 0
    .height: dd 0
    .sprite_ptr: dd 0
    .scale: dd 0
    .transparent: dd 0
    .color: dd 0
    .row: dd 0
    .col: dd 0
    .sx: dd 0
    .sy: dd 0

; ========================================
; SPRITE DATA (SOME DEMO SPRITES)
; ========================================

; 8x8 smiley face
sprite_smiley:
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 0, 14, 14, 14, 14, 0, 0
    db 0, 14, 14, 14, 14, 14, 14, 0
    db 0, 14, 0, 14, 14, 0, 14, 0      ; eyes
    db 0, 14, 14, 14, 14, 14, 14, 0
    db 0, 14, 0, 14, 14, 0, 14, 0      ; mouth
    db 0, 0, 14, 0, 0, 14, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0

; 8x8 heart
sprite_heart:
    db 0, 0, 0, 0, 0, 0, 0, 0
    db 0, 12, 12, 0, 0, 12, 12, 0
    db 12, 12, 12, 12, 12, 12, 12, 12
    db 12, 12, 12, 12, 12, 12, 12, 12
    db 0, 12, 12, 12, 12, 12, 12, 0
    db 0, 0, 12, 12, 12, 12, 0, 0
    db 0, 0, 0, 12, 12, 0, 0, 0
    db 0, 0, 0, 0, 0, 0, 0, 0

; 16x16 player character (simple dude)
sprite_player:
    ; row 1
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ; row 2
    db 0, 0, 0, 0, 0, 0, 14, 14, 14, 14, 0, 0, 0, 0, 0, 0
    ; row 3
    db 0, 0, 0, 0, 0, 14, 14, 14, 14, 14, 14, 0, 0, 0, 0, 0
    ; row 4
    db 0, 0, 0, 0, 0, 14, 0, 14, 14, 0, 14, 0, 0, 0, 0, 0
    ; row 5
    db 0, 0, 0, 0, 0, 14, 14, 14, 14, 14, 14, 0, 0, 0, 0, 0
    ; row 6
    db 0, 0, 0, 0, 0, 0, 14, 4, 4, 14, 0, 0, 0, 0, 0, 0
    ; row 7
    db 0, 0, 0, 0, 0, 0, 0, 14, 14, 0, 0, 0, 0, 0, 0, 0
    ; row 8
    db 0, 0, 0, 0, 1, 1, 1, 14, 14, 1, 1, 1, 0, 0, 0, 0
    ; row 9
    db 0, 0, 0, 0, 0, 1, 1, 14, 14, 1, 1, 0, 0, 0, 0, 0
    ; row 10
    db 0, 0, 0, 0, 0, 1, 1, 14, 14, 1, 1, 0, 0, 0, 0, 0
    ; row 11
    db 0, 0, 0, 0, 0, 1, 1, 14, 14, 1, 1, 0, 0, 0, 0, 0
    ; row 12
    db 0, 0, 0, 0, 0, 0, 0, 14, 14, 0, 0, 0, 0, 0, 0, 0
    ; row 13
    db 0, 0, 0, 0, 0, 0, 14, 0, 0, 14, 0, 0, 0, 0, 0, 0
    ; row 14
    db 0, 0, 0, 0, 0, 6, 14, 0, 0, 14, 6, 0, 0, 0, 0, 0
    ; row 15
    db 0, 0, 0, 0, 6, 6, 0, 0, 0, 0, 6, 6, 0, 0, 0, 0
    ; row 16
    db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

; ========================================
; GRAPHICS TEXT (8x8 BITMAP FONT)
; ========================================

; simple 8x8 bitmap font for common characters
; Each character is 8 bytes (8 rows of 8 pixels)
font_8x8:
    ; Space (0x20)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; ! (0x21)
    db 0x18, 0x18, 0x18, 0x18, 0x00, 0x00, 0x18, 0x00
    ; " (0x22)
    db 0x36, 0x36, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ; # (0x23)
    db 0x36, 0x36, 0x7F, 0x36, 0x7F, 0x36, 0x36, 0x00
    ; $ (0x24)
    db 0x0C, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x0C, 0x00
    ; % (0x25)
    db 0x00, 0x63, 0x33, 0x18, 0x0C, 0x66, 0x63, 0x00
    ; & (0x26)
    db 0x1C, 0x36, 0x1C, 0x6E, 0x3B, 0x33, 0x6E, 0x00
    ; ' (0x27)
    db 0x06, 0x06, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00
    ; ( (0x28)
    db 0x18, 0x0C, 0x06, 0x06, 0x06, 0x0C, 0x18, 0x00
    ; ) (0x29)
    db 0x06, 0x0C, 0x18, 0x18, 0x18, 0x0C, 0x06, 0x00
    ; * (0x2A)
    db 0x00, 0x66, 0x3C, 0xFF, 0x3C, 0x66, 0x00, 0x00
    ; + (0x2B)
    db 0x00, 0x0C, 0x0C, 0x3F, 0x0C, 0x0C, 0x00, 0x00
    ; , (0x2C)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x06
    ; - (0x2D)
    db 0x00, 0x00, 0x00, 0x3F, 0x00, 0x00, 0x00, 0x00
    ; . (0x2E)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x00
    ; / (0x2F)
    db 0x60, 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01, 0x00
    ; 0 (0x30)
    db 0x3E, 0x63, 0x73, 0x7B, 0x6F, 0x67, 0x3E, 0x00
    ; 1 (0x31)
    db 0x0C, 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x3F, 0x00
    ; 2 (0x32)
    db 0x1E, 0x33, 0x30, 0x1C, 0x06, 0x33, 0x3F, 0x00
    ; 3 (0x33)
    db 0x1E, 0x33, 0x30, 0x1C, 0x30, 0x33, 0x1E, 0x00
    ; 4 (0x34)
    db 0x38, 0x3C, 0x36, 0x33, 0x7F, 0x30, 0x78, 0x00
    ; 5 (0x35)
    db 0x3F, 0x03, 0x1F, 0x30, 0x30, 0x33, 0x1E, 0x00
    ; 6 (0x36)
    db 0x1C, 0x06, 0x03, 0x1F, 0x33, 0x33, 0x1E, 0x00
    ; 7 (0x37)
    db 0x3F, 0x33, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x00
    ; 8 (0x38)
    db 0x1E, 0x33, 0x33, 0x1E, 0x33, 0x33, 0x1E, 0x00
    ; 9 (0x39)
    db 0x1E, 0x33, 0x33, 0x3E, 0x30, 0x18, 0x0E, 0x00
    ; : (0x3A)
    db 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x00
    ; ; (0x3B)
    db 0x00, 0x0C, 0x0C, 0x00, 0x00, 0x0C, 0x0C, 0x06
    ; < (0x3C)
    db 0x18, 0x0C, 0x06, 0x03, 0x06, 0x0C, 0x18, 0x00
    ; = (0x3D)
    db 0x00, 0x00, 0x3F, 0x00, 0x00, 0x3F, 0x00, 0x00
    ; > (0x3E)
    db 0x06, 0x0C, 0x18, 0x30, 0x18, 0x0C, 0x06, 0x00
    ; ? (0x3F)
    db 0x1E, 0x33, 0x30, 0x18, 0x0C, 0x00, 0x0C, 0x00
    ; @ (0x40)
    db 0x3E, 0x63, 0x7B, 0x7B, 0x7B, 0x03, 0x1E, 0x00
    ; A (0x41)
    db 0x0C, 0x1E, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x00
    ; B (0x42)
    db 0x3F, 0x66, 0x66, 0x3E, 0x66, 0x66, 0x3F, 0x00
    ; C (0x43)
    db 0x3C, 0x66, 0x03, 0x03, 0x03, 0x66, 0x3C, 0x00
    ; D (0x44)
    db 0x1F, 0x36, 0x66, 0x66, 0x66, 0x36, 0x1F, 0x00
    ; E (0x45)
    db 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x46, 0x7F, 0x00
    ; F (0x46)
    db 0x7F, 0x46, 0x16, 0x1E, 0x16, 0x06, 0x0F, 0x00
    ; G (0x47)
    db 0x3C, 0x66, 0x03, 0x03, 0x73, 0x66, 0x7C, 0x00
    ; H (0x48)
    db 0x33, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x33, 0x00
    ; I (0x49)
    db 0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00
    ; J (0x4A)
    db 0x78, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E, 0x00
    ; K (0x4B)
    db 0x67, 0x66, 0x36, 0x1E, 0x36, 0x66, 0x67, 0x00
    ; L (0x4C)
    db 0x0F, 0x06, 0x06, 0x06, 0x46, 0x66, 0x7F, 0x00
    ; M (0x4D)
    db 0x63, 0x77, 0x7F, 0x7F, 0x6B, 0x63, 0x63, 0x00
    ; N (0x4E)
    db 0x63, 0x67, 0x6F, 0x7B, 0x73, 0x63, 0x63, 0x00
    ; O (0x4F)
    db 0x1C, 0x36, 0x63, 0x63, 0x63, 0x36, 0x1C, 0x00
    ; P (0x50)
    db 0x3F, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x0F, 0x00
    ; Q (0x51)
    db 0x1E, 0x33, 0x33, 0x33, 0x3B, 0x1E, 0x38, 0x00
    ; R (0x52)
    db 0x3F, 0x66, 0x66, 0x3E, 0x36, 0x66, 0x67, 0x00
    ; S (0x53)
    db 0x1E, 0x33, 0x07, 0x0E, 0x38, 0x33, 0x1E, 0x00
    ; T (0x54)
    db 0x3F, 0x2D, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00
    ; U (0x55)
    db 0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x3F, 0x00
    ; V (0x56)
    db 0x33, 0x33, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00
    ; W (0x57)
    db 0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00
    ; X (0x58)
    db 0x63, 0x63, 0x36, 0x1C, 0x1C, 0x36, 0x63, 0x00
    ; Y (0x59)
    db 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x0C, 0x1E, 0x00
    ; Z (0x5A)
    db 0x7F, 0x63, 0x31, 0x18, 0x4C, 0x66, 0x7F, 0x00
    ; [ (0x5B)
    db 0x1E, 0x06, 0x06, 0x06, 0x06, 0x06, 0x1E, 0x00
    ; \ (0x5C)
    db 0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x40, 0x00
    ; ] (0x5D)
    db 0x1E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x1E, 0x00
    ; ^ (0x5E)
    db 0x08, 0x1C, 0x36, 0x63, 0x00, 0x00, 0x00, 0x00
    ; _ (0x5F)
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF
    ; ` (0x60)
    db 0x0C, 0x0C, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00
    ; a (0x61)
    db 0x00, 0x00, 0x1E, 0x30, 0x3E, 0x33, 0x6E, 0x00
    ; b (0x62)
    db 0x07, 0x06, 0x06, 0x3E, 0x66, 0x66, 0x3B, 0x00
    ; c (0x63)
    db 0x00, 0x00, 0x1E, 0x33, 0x03, 0x33, 0x1E, 0x00
    ; d (0x64)
    db 0x38, 0x30, 0x30, 0x3e, 0x33, 0x33, 0x6E, 0x00
    ; e (0x65)
    db 0x00, 0x00, 0x1E, 0x33, 0x3f, 0x03, 0x1E, 0x00
    ; f (0x66)
    db 0x1C, 0x36, 0x06, 0x0f, 0x06, 0x06, 0x0F, 0x00
    ; g (0x67)
    db 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x1F
    ; h (0x68)
    db 0x07, 0x06, 0x36, 0x6E, 0x66, 0x66, 0x67, 0x00
    ; i (0x69)
    db 0x0C, 0x00, 0x0E, 0x0C, 0x0C, 0x0C, 0x1E, 0x00
    ; j (0x6A)
    db 0x30, 0x00, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E
    ; k (0x6B)
    db 0x07, 0x06, 0x66, 0x36, 0x1E, 0x36, 0x67, 0x00
    ; l (0x6C)
    db 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00
    ; m (0x6D)
    db 0x00, 0x00, 0x33, 0x7F, 0x7F, 0x6B, 0x63, 0x00
    ; n (0x6E)
    db 0x00, 0x00, 0x1F, 0x33, 0x33, 0x33, 0x33, 0x00
    ; o (0x6F)
    db 0x00, 0x00, 0x1E, 0x33, 0x33, 0x33, 0x1E, 0x00
    ; p (0x70)
    db 0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F
    ; q (0x71)
    db 0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x78
    ; r (0x72)
    db 0x00, 0x00, 0x3B, 0x6E, 0x66, 0x06, 0x0F, 0x00
    ; s (0x73)
    db 0x00, 0x00, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x00
    ; t (0x74)
    db 0x08, 0x0C, 0x3E, 0x0C, 0x0C, 0x2C, 0x18, 0x00
    ; u (0x75)
    db 0x00, 0x00, 0x33, 0x33, 0x33, 0x33, 0x6E, 0x00
    ; v (0x76)
    db 0x00, 0x00, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00
    ; w (0x77)
    db 0x00, 0x00, 0x63, 0x6B, 0x7F, 0x7F, 0x36, 0x00
    ; x (0x78)
    db 0x00, 0x00, 0x63, 0x36, 0x1C, 0x36, 0x63, 0x00
    ; y (0x79)
    db 0x00, 0x00, 0x33, 0x33, 0x33, 0x3E, 0x30, 0x1F
    ; z (0x7A)
    db 0x00, 0x00, 0x3F, 0x19, 0x0C, 0x26, 0x3F, 0x00

; draw a character in graphics mode
; AL = character ASCII
; EBX = x position
; ECX = y position
; DL = color
draw_char_gfx:
    pusha
    
    ; check if character is in range
    cmp al, 0x20
    jl .done
    cmp al, 0x7A
    jg .done
    
    ; get font data offset
    sub al, 0x20        ; adjust to font table
    movzx eax, al
    shl eax, 3          ; multiply by 8 (8 bytes per char)
    lea esi, [font_8x8 + eax]
    
    ; save position and color
    mov [.x], ebx
    mov [.y], ecx
    mov [.color], dl
    
    ; draw 8 rows
    mov dword [.row], 0
    
    .row_loop:
        cmp dword [.row], 8
        jge .done
        
        ; get row bitmap
        lodsb
        mov [.bitmap], al
        
        ; draw 8 pixels in this row
        mov dword [.col], 0
        
        .col_loop:
            cmp dword [.col], 8
            jge .next_row
            
            ; check if pixel should be drawn
            mov cl, byte [.col]
            mov al, byte [.bitmap]
            shr al, cl
            test al, 1
            jz .skip_pixel
            
            ; draw the pixel
            mov eax, [.x]
            add eax, 7
            sub eax, [.col]     ; reverse bit order
            mov ebx, [.y]
            add ebx, [.row]
            mov cl, byte [.color]
            call plot_pixel
            
            .skip_pixel:
            inc dword [.col]
            jmp .col_loop
        
        .next_row:
        inc dword [.row]
        jmp .row_loop
    
    .done:
    popa
    ret
    
    .x: dd 0
    .y: dd 0
    .color: db 0
    .bitmap: db 0
    .row: dd 0
    .col: dd 0

; draw a string in graphics mode
; ESI = string pointer (null-terminated)
; EAX = x position
; EBX = y position
; DL = color
draw_string_gfx:
    pusha
    
    mov [.x], eax
    mov [.y], ebx
    mov [.color], dl
    
    .loop:
        lodsb
        test al, al
        jz .done
        
        ; draw character
        mov ebx, [.x]
        mov ecx, [.y]
        mov dl, byte [.color]
        call draw_char_gfx
        
        ; advance x position
        add dword [.x], 8
        jmp .loop
    
    .done:
    popa
    ret
    
    .x: dd 0
    .y: dd 0
    .color: db 0

; ========================================
; DEMO FUNCTIONS
; ========================================

; draw some demo shit to test graphics
graphics_demo:
    pusha
    
    ; clear screen to dark blue
    mov al, 17              ; dark blue
    call clear_graphics_screen
    
    ; draw title text
    mov esi, .title_text
    mov eax, 80
    mov ebx, 10
    mov dl, 15              ; white
    call draw_string_gfx
    
    ; draw a red rectangle
    mov eax, 50
    mov ebx, 50
    mov ecx, 150
    mov edx, 100
    push COLOR_RED
    call draw_filled_rect
    add esp, 4
    
    ; draw label for shapes
    mov esi, .shapes_label
    mov eax, 60
    mov ebx, 110
    mov dl, 14              ; yellow
    call draw_string_gfx
    
    ; draw a blue outline
    mov eax, 55
    mov ebx, 55
    mov ecx, 145
    mov edx, 95
    push COLOR_LIGHT_BLUE
    call draw_rect
    add esp, 4
    
    ; draw a diagonal line
    mov eax, 10
    mov ebx, 10
    mov ecx, 100
    mov edx, 100
    push COLOR_YELLOW
    call draw_line
    add esp, 4
    
    ; draw another line
    mov eax, 100
    mov ebx, 10
    mov ecx, 10
    mov edx, 100
    push COLOR_GREEN
    call draw_line
    add esp, 4
    
    ; draw some horizontal lines
    mov eax, 200
    mov ebx, 50
    mov ecx, 310
    mov dl, COLOR_CYAN
    call draw_hline
    
    mov eax, 200
    mov ebx, 60
    mov ecx, 310
    mov dl, COLOR_MAGENTA
    call draw_hline
    
    mov eax, 200
    mov ebx, 70
    mov ecx, 310
    mov dl, COLOR_YELLOW
    call draw_hline
    
    ; draw sprite label
    mov esi, .sprites_label
    mov eax, 160
    mov ebx, 30
    mov dl, 10              ; green
    call draw_string_gfx
    
    ; draw some sprites baby!
    ; smiley face at (160, 45)
    mov esi, sprite_smiley
    mov eax, 160
    ; heart at (180, 45)
    mov esi, sprite_heart
    mov eax, 180
    mov ebx, 45
    mov ecx, 8
    mov edx, 8
    push 0
    call draw_sprite
    add esp, 4
    
    ; scaled smiley (2x) at (200, 60)
    mov esi, sprite_smiley
    mov eax, 200
    mov ebx, 60
    mov ecx, 8
    mov edx, 8
    push 0          ; transparent
    push 2          ; scale 2x
    call draw_sprite_scaled
    add esp, 8
    
    ; player sprite at (140, 120)
    mov esi, sprite_player
    mov eax, 140
    mov ebx, 120
    mov ecx, 16
    mov edx, 16
    push 0
    call draw_sprite
    add esp, 4
    
    ; scaled player (3x) at (20, 120)
    mov esi, sprite_player
    mov eax, 20
    mov ebx, 120
    mov ecx, 16
    mov edx, 16
    push 0          ; transparent
    push 3          ; scale 3x
    call draw_sprite_scaled
    add esp, 8
    
    popa
    ret
    
    .title_text: db 'j3kOS Graphics Demo', 0
    .shapes_label: db 'Shapes', 0
    .sprites_label: db 'Sprites:', 0
