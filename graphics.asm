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
; GRAPHICS TEXT (8x8 BITMAP FONT)
; ========================================

; simple 8x8 font (just a few chars for demo)
; 1 = pixel on, 0 = pixel off
font_8x8:
    ; character 'A' (0x41)
    db 0x00, 0x18, 0x24, 0x42, 0x42, 0x7E, 0x42, 0x42
    ; character 'B'
    db 0x00, 0x7C, 0x42, 0x7C, 0x42, 0x42, 0x7C, 0x00
    ; character 'C'
    db 0x00, 0x3C, 0x42, 0x40, 0x40, 0x42, 0x3C, 0x00
    ; TODO: add more chars as needed

; draw a character in graphics mode
; AL = character
; EBX = x
; ECX = y
; DL = color
draw_char_gfx:
    pusha
    
    ; for now just draw a placeholder rectangle
    mov eax, ebx
    mov ebx, ecx
    add ecx, 7
    add eax, 7
    push edx
    call draw_rect
    add esp, 4
    
    popa
    ret

; ========================================
; DEMO FUNCTIONS
; ========================================

; draw some demo shit to test graphics
graphics_demo:
    pusha
    
    ; clear screen to black
    mov al, COLOR_BLACK
    call clear_graphics_screen
    
    ; draw a red rectangle
    mov eax, 50
    mov ebx, 50
    mov ecx, 150
    mov edx, 100
    push COLOR_RED
    call draw_filled_rect
    add esp, 4
    
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
    
    popa
    ret
