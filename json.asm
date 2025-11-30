; =====================================================
; JSON PARSER - JAVASCRIPT OBJECT NOTATION
; parse objects, arrays, strings, numbers, booleans
; =====================================================

; JSON token types
JSON_TOKEN_OBJECT_START     equ 1   ; {
JSON_TOKEN_OBJECT_END       equ 2   ; }
JSON_TOKEN_ARRAY_START      equ 3   ; [
JSON_TOKEN_ARRAY_END        equ 4   ; ]
JSON_TOKEN_STRING           equ 5   ; "string"
JSON_TOKEN_NUMBER           equ 6   ; 123
JSON_TOKEN_TRUE             equ 7   ; true
JSON_TOKEN_FALSE            equ 8   ; false
JSON_TOKEN_NULL             equ 9   ; null
JSON_TOKEN_COLON            equ 10  ; :
JSON_TOKEN_COMMA            equ 11  ; ,

; JSON value types
JSON_TYPE_OBJECT    equ 1
JSON_TYPE_ARRAY     equ 2
JSON_TYPE_STRING    equ 3
JSON_TYPE_NUMBER    equ 4
JSON_TYPE_BOOLEAN   equ 5
JSON_TYPE_NULL      equ 6

; JSON node structure (32 bytes)
struc JSON_NODE
    .type:          resb 1      ; JSON_TYPE_*
    .parent:        resd 1      ; pointer to parent node
    .key:           resd 1      ; pointer to key string (if object property)
    .value:         resd 1      ; pointer to value (string or number)
    .first_child:   resd 1      ; first child node
    .next_sibling:  resd 1      ; next sibling node
    .padding:       resb 8      ; pad to 32 bytes
endstruc

; JSON parser state
json_buffer:        times 2048 db 0
json_nodes:         times (64 * 32) db 0    ; 64 nodes max
json_node_count:    dd 0
json_current_pos:   dd 0

; ========================================
; JSON TOKENIZER
; ========================================

; Get next JSON token
; ESI = JSON string
; Returns: AL = token type, ESI = next position
json_next_token:
    push ebx
    
    ; skip whitespace
.skip_whitespace:
    lodsb
    cmp al, ' '
    je .skip_whitespace
    cmp al, 9                   ; tab
    je .skip_whitespace
    cmp al, 10                  ; newline
    je .skip_whitespace
    cmp al, 13                  ; carriage return
    je .skip_whitespace
    
    ; check token type
    cmp al, '{'
    je .object_start
    cmp al, '}'
    je .object_end
    cmp al, '['
    je .array_start
    cmp al, ']'
    je .array_end
    cmp al, ':'
    je .colon
    cmp al, ','
    je .comma
    cmp al, '"'
    je .string
    cmp al, 't'
    je .check_true
    cmp al, 'f'
    je .check_false
    cmp al, 'n'
    je .check_null
    
    ; must be number or invalid
    cmp al, '-'
    je .number
    cmp al, '0'
    jb .invalid
    cmp al, '9'
    ja .invalid
    jmp .number
    
.object_start:
    mov al, JSON_TOKEN_OBJECT_START
    jmp .done
    
.object_end:
    mov al, JSON_TOKEN_OBJECT_END
    jmp .done
    
.array_start:
    mov al, JSON_TOKEN_ARRAY_START
    jmp .done
    
.array_end:
    mov al, JSON_TOKEN_ARRAY_END
    jmp .done
    
.colon:
    mov al, JSON_TOKEN_COLON
    jmp .done
    
.comma:
    mov al, JSON_TOKEN_COMMA
    jmp .done
    
.string:
    mov al, JSON_TOKEN_STRING
    ; string value is parsed separately
    jmp .done
    
.number:
    dec esi                     ; back up to number start
    mov al, JSON_TOKEN_NUMBER
    jmp .done
    
.check_true:
    ; check if "true"
    cmp dword [esi-1], 'true'
    jne .invalid
    add esi, 3
    mov al, JSON_TOKEN_TRUE
    jmp .done
    
.check_false:
    ; check if "false"
    cmp dword [esi-1], 'fals'
    jne .invalid
    cmp byte [esi+3], 'e'
    jne .invalid
    add esi, 4
    mov al, JSON_TOKEN_FALSE
    jmp .done
    
.check_null:
    ; check if "null"
    cmp dword [esi-1], 'null'
    jne .invalid
    add esi, 3
    mov al, JSON_TOKEN_NULL
    jmp .done
    
.invalid:
    xor al, al
    
.done:
    pop ebx
    ret

; ========================================
; JSON PARSER
; ========================================

; Parse JSON string
; ESI = JSON string
; Returns: EAX = pointer to root JSON_NODE
json_parse:
    pusha
    
    ; initialize
    mov dword [json_node_count], 0
    mov [.json_start], esi
    
    ; get first token
    call json_next_token
    
    cmp al, JSON_TOKEN_OBJECT_START
    je .parse_object
    cmp al, JSON_TOKEN_ARRAY_START
    je .parse_array
    jmp .error
    
.parse_object:
    call json_parse_object
    mov [.root_node], eax
    jmp .success
    
.parse_array:
    call json_parse_array
    mov [.root_node], eax
    jmp .success
    
.success:
    popa
    mov eax, [.root_node]
    ret
    
.error:
    popa
    xor eax, eax
    ret

.json_start:    dd 0
.root_node:     dd 0

; Parse JSON object
; ESI = position after '{'
; Returns: EAX = pointer to object node
json_parse_object:
    push ebx
    push ecx
    push edx
    
    ; create object node
    call json_create_node
    mov [.object_node], eax
    mov byte [eax + JSON_NODE.type], JSON_TYPE_OBJECT
    
    mov ebx, eax                ; save object node
    xor ecx, ecx                ; last child
    
.parse_property:
    ; get next token (should be string key or })
    call json_next_token
    
    cmp al, JSON_TOKEN_OBJECT_END
    je .done
    
    cmp al, JSON_TOKEN_STRING
    jne .error
    
    ; parse key string
    push esi
    call json_parse_string
    mov [.key_ptr], eax
    pop esi
    
    ; expect colon
    call json_next_token
    cmp al, JSON_TOKEN_COLON
    jne .error
    
    ; parse value
    call json_parse_value
    test eax, eax
    jz .error
    
    ; set key
    mov edx, [.key_ptr]
    mov [eax + JSON_NODE.key], edx
    
    ; link to object
    test ecx, ecx
    jz .first_child
    
    ; add as sibling
    mov [ecx + JSON_NODE.next_sibling], eax
    jmp .update_last
    
.first_child:
    mov [ebx + JSON_NODE.first_child], eax
    
.update_last:
    mov ecx, eax                ; update last child
    mov [eax + JSON_NODE.parent], ebx
    
    ; check for comma or end
    call json_next_token
    cmp al, JSON_TOKEN_COMMA
    je .parse_property
    cmp al, JSON_TOKEN_OBJECT_END
    je .done
    jmp .error
    
.done:
    mov eax, [.object_node]
    pop edx
    pop ecx
    pop ebx
    ret
    
.error:
    xor eax, eax
    pop edx
    pop ecx
    pop ebx
    ret

.object_node:   dd 0
.key_ptr:       dd 0

; Parse JSON array
; ESI = position after '['
; Returns: EAX = pointer to array node
json_parse_array:
    push ebx
    push ecx
    
    ; create array node
    call json_create_node
    mov [.array_node], eax
    mov byte [eax + JSON_NODE.type], JSON_TYPE_ARRAY
    
    mov ebx, eax                ; save array node
    xor ecx, ecx                ; last child
    
.parse_element:
    ; peek next token
    push esi
    call json_next_token
    mov dl, al
    pop esi
    
    cmp dl, JSON_TOKEN_ARRAY_END
    je .check_end
    
    ; parse value
    call json_parse_value
    test eax, eax
    jz .error
    
    ; link to array
    test ecx, ecx
    jz .first_child
    
    mov [ecx + JSON_NODE.next_sibling], eax
    jmp .update_last
    
.first_child:
    mov [ebx + JSON_NODE.first_child], eax
    
.update_last:
    mov ecx, eax
    mov [eax + JSON_NODE.parent], ebx
    
    ; check for comma or end
    call json_next_token
    cmp al, JSON_TOKEN_COMMA
    je .parse_element
    cmp al, JSON_TOKEN_ARRAY_END
    je .done
    jmp .error
    
.check_end:
    call json_next_token
    
.done:
    mov eax, [.array_node]
    pop ecx
    pop ebx
    ret
    
.error:
    xor eax, eax
    pop ecx
    pop ebx
    ret

.array_node:    dd 0

; Parse JSON value (any type)
; ESI = position before value
; Returns: EAX = pointer to value node
json_parse_value:
    push ebx
    
    ; get token
    call json_next_token
    mov bl, al
    
    cmp bl, JSON_TOKEN_OBJECT_START
    je .object
    cmp bl, JSON_TOKEN_ARRAY_START
    je .array
    cmp bl, JSON_TOKEN_STRING
    je .string
    cmp bl, JSON_TOKEN_NUMBER
    je .number
    cmp bl, JSON_TOKEN_TRUE
    je .true
    cmp bl, JSON_TOKEN_FALSE
    je .false
    cmp bl, JSON_TOKEN_NULL
    je .null
    jmp .error
    
.object:
    call json_parse_object
    jmp .done
    
.array:
    call json_parse_array
    jmp .done
    
.string:
    push esi
    call json_parse_string
    pop esi
    
    push eax
    call json_create_node
    mov byte [eax + JSON_NODE.type], JSON_TYPE_STRING
    pop ebx
    mov [eax + JSON_NODE.value], ebx
    jmp .done
    
.number:
    dec esi                     ; back up
    push esi
    call json_parse_number
    pop esi
    
    push eax
    call json_create_node
    mov byte [eax + JSON_NODE.type], JSON_TYPE_NUMBER
    pop ebx
    mov [eax + JSON_NODE.value], ebx
    jmp .done
    
.true:
    call json_create_node
    mov byte [eax + JSON_NODE.type], JSON_TYPE_BOOLEAN
    mov dword [eax + JSON_NODE.value], 1
    jmp .done
    
.false:
    call json_create_node
    mov byte [eax + JSON_NODE.type], JSON_TYPE_BOOLEAN
    mov dword [eax + JSON_NODE.value], 0
    jmp .done
    
.null:
    call json_create_node
    mov byte [eax + JSON_NODE.type], JSON_TYPE_NULL
    jmp .done
    
.error:
    xor eax, eax
    
.done:
    pop ebx
    ret

; Parse JSON string (between quotes)
; ESI = position after opening quote
; Returns: EAX = pointer to string in buffer
json_parse_string:
    push edi
    push esi
    
    mov edi, json_buffer
    add edi, [json_current_pos]
    mov [.string_start], edi
    
.loop:
    lodsb
    
    cmp al, '"'
    je .done
    
    cmp al, '\'
    je .escape
    
    stosb
    jmp .loop
    
.escape:
    ; handle escape sequence
    lodsb
    cmp al, 'n'
    je .newline
    cmp al, 't'
    je .tab
    stosb
    jmp .loop
    
.newline:
    mov al, 10
    stosb
    jmp .loop
    
.tab:
    mov al, 9
    stosb
    jmp .loop
    
.done:
    ; null terminate
    xor al, al
    stosb
    
    ; update buffer position
    mov eax, edi
    sub eax, json_buffer
    mov [json_current_pos], eax
    
    pop esi
    pop edi
    mov eax, [.string_start]
    ret

.string_start:  dd 0

; Parse JSON number
; ESI = position at number start
; Returns: EAX = number value
json_parse_number:
    push ebx
    push ecx
    
    xor eax, eax
    xor ebx, ebx
    mov cl, 1                   ; sign (positive)
    
    ; check for negative
    cmp byte [esi], '-'
    jne .parse_digits
    inc esi
    mov cl, -1
    
.parse_digits:
    movzx ebx, byte [esi]
    
    cmp bl, '0'
    jb .done
    cmp bl, '9'
    ja .done
    
    imul eax, 10
    sub bl, '0'
    add eax, ebx
    
    inc esi
    jmp .parse_digits
    
.done:
    test cl, cl
    jns .positive
    neg eax
    
.positive:
    pop ecx
    pop ebx
    ret

; ========================================
; JSON BUILDER
; ========================================

; Build JSON string from node tree
; EAX = root node, EDI = output buffer
; Returns: ECX = length
json_build:
    push eax
    push esi
    
    mov esi, eax
    mov [.start_pos], edi
    
    ; check type
    mov al, [esi + JSON_NODE.type]
    cmp al, JSON_TYPE_OBJECT
    je .build_object
    cmp al, JSON_TYPE_ARRAY
    je .build_array
    
    ; simple value
    call json_build_value
    jmp .done
    
.build_object:
    call json_build_object
    jmp .done
    
.build_array:
    call json_build_array
    
.done:
    mov ecx, edi
    sub ecx, [.start_pos]
    
    pop esi
    pop eax
    ret

.start_pos: dd 0

; Build JSON object
; ESI = object node, EDI = output buffer
json_build_object:
    push eax
    push ebx
    
    mov al, '{'
    stosb
    
    ; iterate children
    mov ebx, [esi + JSON_NODE.first_child]
    test ebx, ebx
    jz .close
    
.build_property:
    ; write key
    mov al, '"'
    stosb
    
    push esi
    mov esi, [ebx + JSON_NODE.key]
    call http_copy_string
    pop esi
    
    mov ax, '":'
    stosw
    
    ; write value
    push esi
    mov esi, ebx
    call json_build_value
    pop esi
    
    ; check for more siblings
    mov ebx, [ebx + JSON_NODE.next_sibling]
    test ebx, ebx
    jz .close
    
    mov al, ','
    stosb
    jmp .build_property
    
.close:
    mov al, '}'
    stosb
    
    pop ebx
    pop eax
    ret

; Build JSON array
; ESI = array node, EDI = output buffer
json_build_array:
    push eax
    push ebx
    
    mov al, '['
    stosb
    
    ; iterate children
    mov ebx, [esi + JSON_NODE.first_child]
    test ebx, ebx
    jz .close
    
.build_element:
    push esi
    mov esi, ebx
    call json_build_value
    pop esi
    
    mov ebx, [ebx + JSON_NODE.next_sibling]
    test ebx, ebx
    jz .close
    
    mov al, ','
    stosb
    jmp .build_element
    
.close:
    mov al, ']'
    stosb
    
    pop ebx
    pop eax
    ret

; Build JSON value
; ESI = value node, EDI = output buffer
json_build_value:
    push eax
    push ebx
    
    mov al, [esi + JSON_NODE.type]
    cmp al, JSON_TYPE_OBJECT
    je .object
    cmp al, JSON_TYPE_ARRAY
    je .array
    cmp al, JSON_TYPE_STRING
    je .string
    cmp al, JSON_TYPE_NUMBER
    je .number
    cmp al, JSON_TYPE_BOOLEAN
    je .boolean
    jmp .null
    
.object:
    call json_build_object
    jmp .done
    
.array:
    call json_build_array
    jmp .done
    
.string:
    mov al, '"'
    stosb
    
    push esi
    mov esi, [esi + JSON_NODE.value]
    call http_copy_string
    pop esi
    
    mov al, '"'
    stosb
    jmp .done
    
.number:
    mov eax, [esi + JSON_NODE.value]
    call http_int_to_string
    jmp .done
    
.boolean:
    cmp dword [esi + JSON_NODE.value], 0
    je .false
    
    mov eax, 'true'
    stosd
    jmp .done
    
.false:
    mov eax, 'fals'
    stosd
    mov al, 'e'
    stosb
    jmp .done
    
.null:
    mov eax, 'null'
    stosd
    
.done:
    pop ebx
    pop eax
    ret

; ========================================
; HELPERS
; ========================================

; Create new JSON node
; Returns: EAX = pointer to new node
json_create_node:
    push ebx
    push ecx
    
    mov eax, [json_node_count]
    cmp eax, 64
    jae .error
    
    imul eax, 32
    add eax, json_nodes
    
    ; clear node
    push edi
    mov edi, eax
    mov ecx, 32
    xor al, al
    rep stosb
    pop edi
    
    inc dword [json_node_count]
    
    pop ecx
    pop ebx
    ret
    
.error:
    xor eax, eax
    pop ecx
    pop ebx
    ret
