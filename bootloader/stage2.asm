; stage2.asm - WRK BIOS bootstrap, stage 2 (menu + chainloader)
;
; Loaded at physical 0000:8000 by stage1. Shows an honest banner, then a
; key menu. 'C' reads sector 0 of BIOS drive 80h (first hard disk) and,
; only if it has a 55AA signature and is NOT our own WRK1 bootstrap, far
; jumps to it - a plain MBR chainload. 'R' invokes INT19 (BIOS bootstrap,
; not a full hardware reset). 'H' halts. No PE loading, no protected
; mode, no filesystem or registry parsing.
;
; nasm -f bin -o stage2.bin -l stage2.lst stage2.asm

bits 16
org 0x8000

        jmp     short entry         ; 2-byte jump; bytes 2..5 = 'WRK2'
        db      'WRK2'

entry:
        jmp     0x0000:init         ; normalize CS to 0
init:
        xor     ax, ax
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0x7c00          ; stack below 7C00; stage1 image is dead
        cld
        sti
        mov     [boot_drive], dl    ; preserve original boot drive

        mov     ax, 0x0003          ; int10 mode 03h: 80x25 text, page 0
        int     0x10

        mov     si, msg_banner
        call    puts
        mov     si, msg_stages
        call    puts
        mov     si, msg_kind
        call    puts
        mov     si, msg_winreq
        call    puts
        mov     si, msg_drive
        call    puts
        mov     al, [boot_drive]
        call    puthex8
        mov     si, msg_crlf
        call    puts
        mov     si, msg_menu
        call    puts

menu:
        xor     ah, ah
        int     0x16                ; wait for keypress; AL = ascii
        or      al, 0x20            ; fold to lowercase
        cmp     al, 'c'
        je      chainload
        cmp     al, 'r'
        je      restart
        cmp     al, 'h'
        je      haltmsg
        jmp     menu                ; ignore anything else

restart:
        mov     si, msg_restart
        call    puts
        int     0x19                ; BIOS bootstrap loader (not a hw reset)
        jmp     menu                ; if the BIOS ever returns

haltmsg:
        mov     si, msg_halt
        call    puts
.hang:
        cli
        hlt
        jmp     .hang

; ---------------------------------------------------------------------
; Chainload sector 0 of drive 80h into 0000:7C00 and jump to it.
; ---------------------------------------------------------------------
chainload:
        mov     si, msg_reading
        call    puts

        mov     byte [have_edd], 0
        mov     ah, 0x41            ; INT13 extensions present?
        mov     bx, 0x55AA
        mov     dl, 0x80
        int     0x13
        jc      .noedd
        cmp     bx, 0xAA55
        jne     .noedd
        test    cl, 1               ; bit0: AH=42-44/48 device access
        jz      .noedd
        mov     byte [have_edd], 1
.noedd:
        mov     byte [retries], 3
.read:
        cmp     byte [have_edd], 0
        je      .chs
        mov     byte [dap_blocks], 1   ; DAP count field, reset each retry
        mov     ah, 0x42               ; extended read
        mov     dl, 0x80
        mov     si, dap
        int     0x13
        jmp     .chk
.chs:
        mov     ah, 0x02            ; legacy CHS read: cyl0/head0/sector1
        mov     al, 1
        xor     ch, ch
        mov     cl, 1
        xor     dh, dh
        mov     dl, 0x80
        xor     bx, bx
        mov     es, bx
        mov     bx, 0x7c00
        int     0x13
.chk:
        jnc     .ok
        xor     ah, ah              ; disk reset between attempts
        mov     dl, 0x80
        int     0x13
        dec     byte [retries]
        jnz     .read
        mov     si, msg_nodisk
        call    puts
        jmp     menu

.ok:
        cmp     word [0x7dfe], 0xAA55      ; signature at 7C00+510
        je      .sigok
        mov     si, msg_badsig
        call    puts
        jmp     menu
.sigok:
        cmp     word [0x7c05], 'WR'        ; our own stage1 marker at 5..8?
        jne     .go
        cmp     word [0x7c07], 'K1'
        jne     .go
        mov     si, msg_recur              ; refuse bootstrap recursion
        call    puts
        jmp     menu
.go:
        mov     si, msg_chain
        call    puts
        mov     dl, 0x80                   ; convention: DL = boot drive
        xor     ax, ax
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0x7c00                 ; normalize real-mode state
        cld
        jmp     0x0000:0x7c00              ; hand off to the disk's MBR

puts:                               ; print 0-terminated DS:SI via int10 teletype
        lodsb
        or      al, al
        jz      .done
        mov     ah, 0x0e
        mov     bx, 0x0007          ; page 0
        int     0x10
        jmp     puts
.done:
        ret

puthex8:                            ; print AL as two hex digits
        push    ax
        shr     al, 4
        call    putnib
        pop     ax
        and     al, 0x0f
putnib:                             ; low nibble of AL -> '0'..'F'
        add     al, '0'
        cmp     al, '9'
        jbe     .e
        add     al, 'A'-'0'-10
.e:
        mov     ah, 0x0e
        mov     bx, 0x0007
        int     0x10
        ret

; 16-byte disk address packet for INT13 AH=42
dap:
dap_size:   db 0x10
dap_resv:   db 0
dap_blocks: dw 1                    ; sectors to read (reset before each try)
dap_off:    dw 0x7c00               ; buffer offset
dap_seg:    dw 0x0000               ; buffer segment
dap_lba:    dq 0                    ; LBA 0

boot_drive: db 0
have_edd:   db 0
retries:    db 0

msg_banner:  db 'WRK BIOS Bootstrap', 13, 10, 0
msg_stages:  db 'Stage 1 -> stage 2: OK', 13, 10, 0
msg_kind:    db 'This is a BIOS chainloader, not a WRK kernel loader.', 13, 10, 0
msg_winreq:  db 'Windows components are still required to run WRK.', 13, 10, 0
msg_drive:   db 'Boot drive: 0x', 0
msg_menu:    db 13, 10, '[C] chainload first hard disk   [R] BIOS restart (INT19)   [H] halt', 13, 10, 0
msg_reading: db 'Reading sector 0 of drive 0x80...', 13, 10, 0
msg_nodisk:  db 'Cannot read drive 0x80: disk missing or unreadable.', 13, 10, 0
msg_badsig:  db 'Sector 0 has no 55AA signature - not a bootable disk.', 13, 10, 0
msg_recur:   db 'Refusing to chainload: target is this same WRK1 bootstrap.', 13, 10, 0
msg_chain:   db 'Chainloading BIOS hard disk 0x80...', 13, 10, 0
msg_restart: db 'INT19 BIOS bootstrap restart...', 13, 10, 0
msg_halt:    db 'Halted - safe to power off.', 13, 10, 0
msg_crlf:    db 13, 10, 0

        times 4096-($-$$) db 0      ; stage2 image is exactly 8 sectors
