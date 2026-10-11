; stage1.asm - WRK BIOS bootstrap, stage 1 (512-byte boot sector)
;
; BIOS loads this sector at physical address 0000:7C00 and jumps to it
; with DL = boot drive (00h = first floppy, 80h = first hard disk).
; It loads stage 2 (8 sectors: CHS 0/0/2 through 0/0/9, the rest of the
; first 18-sector track on a 1.44 MB floppy) to 0000:8000 and jumps there.
; Read-only: this code never writes to any disk.
;
; nasm -f bin -o stage1.bin -l stage1.lst stage1.asm

bits 16
org 0x7c00

        jmp     0x0000:start        ; 5-byte far jump: normalizes CS to 0
        db      'WRK1'              ; bytes 5..8: our boot sector marker

start:
        xor     ax, ax
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0x7c00          ; stack grows downward from 7C00
        cld
        sti                         ; interrupts only after stack is valid

        mov     [boot_drive], dl    ; preserve BIOS boot drive

        mov     byte [retries], 3
.load:
        mov     ah, 0x02            ; INT 13h: read sectors
        mov     al, 8               ; 8 sectors
        xor     ch, ch              ; cylinder 0
        mov     cl, 2               ; starting at sector 2
        xor     dh, dh              ; head 0
        mov     dl, [boot_drive]
        xor     bx, bx
        mov     es, bx
        mov     bx, 0x8000          ; buffer = 0000:8000
        int     0x13
        jnc     .loaded
        xor     ah, ah              ; AH=00: disk reset between attempts
        mov     dl, [boot_drive]
        int     0x13
        dec     byte [retries]
        jnz     .load
        mov     si, msg_disk
        call    puts
        jmp     halt

.loaded:
        cmp     word [0x8002], 'WR' ; stage2 magic at 8002..8005
        jne     .badmagic           ; ('WRK2', after 2-byte jmp prefix)
        cmp     word [0x8004], 'K2'
        jne     .badmagic
        mov     dl, [boot_drive]    ; pass the original boot drive on
        jmp     0x0000:0x8000
.badmagic:
        mov     si, msg_magic
        call    puts
        ; fall through: never jump into invalid data

halt:
        mov     si, msg_halt
        call    puts
.hang:
        cli
        hlt
        jmp     .hang

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

boot_drive: db 0
retries:    db 0
msg_disk:   db 'stage1: disk read error', 13, 10, 0
msg_magic:  db 'stage1: invalid stage2', 13, 10, 0
msg_halt:   db 'halted', 13, 10, 0

        times 510-($-$$) db 0
        dw 0xAA55
