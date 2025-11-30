; j3kOS Sound System
; pc speaker beeps and boops baby
; by jortboy3k (@jortboy3k)

; ========================================
; PC SPEAKER CONTROL
; ========================================

; play a tone through the pc speaker
; EAX = frequency in Hz
; EBX = duration in milliseconds
play_tone:
    pusha
    
    ; check if frequency is 0 (silence)
    test eax, eax
    jz .silence
    
    ; calculate divisor for PIT
    ; divisor = 1193180 / frequency
    push edx
    mov edx, 0
    mov ecx, eax
    mov eax, 1193180
    div ecx
    mov ecx, eax
    pop edx
    
    ; send command byte to PIT
    mov al, 0xB6
    out 0x43, al
    
    ; send divisor low byte
    mov al, cl
    out 0x42, al
    
    ; send divisor high byte
    mov al, ch
    out 0x42, al
    
    ; turn on speaker
    in al, 0x61
    or al, 3
    out 0x61, al
    
    ; wait for duration
    call .wait_ms
    
    ; turn off speaker
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    
    popa
    ret
    
    .silence:
        ; just wait without playing
        call .wait_ms
        popa
        ret
    
    .wait_ms:
        ; wait EBX milliseconds
        ; rough timing using loop
        push ecx
        mov ecx, ebx
        .wait_loop:
            push ecx
            mov ecx, 1000
            .inner:
                nop
                loop .inner
            pop ecx
            loop .wait_loop
        pop ecx
        ret

; play a beep (default tone)
beep:
    pusha
    mov eax, 800        ; 800 Hz
    mov ebx, 100        ; 100 ms
    call play_tone
    popa
    ret

; play error sound
beep_error:
    pusha
    mov eax, 200        ; low tone
    mov ebx, 300        ; longer
    call play_tone
    popa
    ret

; play success sound
beep_success:
    pusha
    ; two ascending tones
    mov eax, 600
    mov ebx, 80
    call play_tone
    
    mov eax, 900
    mov ebx, 80
    call play_tone
    popa
    ret

; play startup sound
play_startup_sound:
    pusha
    ; quick three beeps
    mov eax, 800
    mov ebx, 50
    call play_tone
    
    mov eax, 1000
    mov ebx, 50
    call play_tone
    
    mov eax, 1200
    mov ebx, 80
    call play_tone
    popa
    ret

; ========================================
; MESSAGES
; ========================================

msg_playing_tone: db 'playing tone...', 10, 0
msg_melody_done: db 'beep!', 10, 0
