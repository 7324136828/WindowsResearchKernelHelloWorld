/*
 * PROJECT:         ReactOS Boot Loader
 * LICENSE:         BSD - See COPYING.ARM in the top level directory
 * FILE:            _bootldr/armllb/inc/keyboard.h
 * PURPOSE:         LLB Keyboard Functions
 * PROGRAMMERS:     ReactOS Portable Systems Group
 */

CHAR
NTAPI
LlbKeyboardGetChar(
    VOID
);

CHAR
NTAPI
LlbKeypadGetChar(
    VOID
);

/* EOF */
