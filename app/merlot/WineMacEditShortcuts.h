/* SPDX-License-Identifier: MIT
 * Translate only standard edit chords not already consumed by the native menu.
 * Physical Control/Option, ordinary letters and game movement keys are untouched.
 */
#ifndef CHARDONNAY_WINE_MAC_EDIT_SHORTCUTS_H
#define CHARDONNAY_WINE_MAC_EDIT_SHORTCUTS_H
#include <stdlib.h>
#include <string.h>

static NSEvent *chardonnayMacEditEvent(NSEvent *event)
{
    const char *enabled = getenv("CHARDONNAY_MAC_SHORTCUTS");
    NSUInteger flags = [event modifierFlags];
    unsigned short code = [event keyCode];
    if (enabled && !strcmp(enabled, "0")) return event;
    if (!(flags & NSEventModifierFlagCommand) ||
         (flags & (NSEventModifierFlagControl | NSEventModifierFlagOption |
                   NSEventModifierFlagShift))) return event;
    if (code != kVK_ANSI_A && code != kVK_ANSI_C && code != kVK_ANSI_V &&
        code != kVK_ANSI_X && code != kVK_ANSI_Z) return event;

    flags &= ~(NSEventModifierFlagCommand | NX_DEVICELCMDKEYMASK | NX_DEVICERCMDKEYMASK);
    flags |= NSEventModifierFlagControl | NX_DEVICELCTLKEYMASK;
    return [NSEvent keyEventWithType:[event type] location:[event locationInWindow]
                      modifierFlags:flags timestamp:[event timestamp]
                       windowNumber:[event windowNumber] context:nil
                         characters:[event characters]
        charactersIgnoringModifiers:[event charactersIgnoringModifiers]
                           isARepeat:[event isARepeat] keyCode:code];
}
#endif
