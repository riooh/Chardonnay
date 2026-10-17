/* SPDX-License-Identifier: MIT
 * Chardonnay's native macOS menu defaults. Include from winemac.drv/cocoa_app.m.
 * No Win32 event ABI changes, global hooks, modifier remapping or forced exits.
 */
#ifndef CHARDONNAY_WINE_MAC_SHORTCUTS_H
#define CHARDONNAY_WINE_MAC_SHORTCUTS_H
#include <stdlib.h>
#include <string.h>

#ifdef CHARDONNAY_SHORTCUT_TESTING
static void chardonnayShortcutProbeStart(void);
#endif

static void chardonnayConfigureMacShortcuts(NSMenu *mainMenu, NSMenu *windowMenu)
{
    const char *enabled = getenv("CHARDONNAY_MAC_SHORTCUTS");
    if (enabled && !strcmp(enabled, "0")) return;

    for (NSMenuItem *parent in [mainMenu itemArray])
    {
        for (NSMenuItem *item in [[parent submenu] itemArray])
        {
            SEL action = [item action];
            if (action == @selector(terminate:))
            {
                [item setKeyEquivalent:@"q"];
                [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
            }
            else if (action == @selector(hide:))
            {
                [item setKeyEquivalent:@"h"];
                [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
            }
            else if (action == @selector(performMiniaturize:))
            {
                [item setKeyEquivalent:@"m"];
                [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
            }
            else if (action == @selector(toggleFullScreen:))
            {
                [item setKeyEquivalent:@"f"];
                [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand |
                                                   NSEventModifierFlagControl];
            }
        }
    }

    // Responder-chain close is the native titlebar-close path, not ExitProcess.
    if ([windowMenu indexOfItemWithTarget:nil andAction:@selector(performClose:)] < 0)
    {
        NSMenuItem *close = [windowMenu insertItemWithTitle:@"Close"
                                                   action:@selector(performClose:)
                                            keyEquivalent:@"w" atIndex:0];
        [close setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    }
#ifdef CHARDONNAY_SHORTCUT_TESTING
    chardonnayShortcutProbeStart();
#endif
}

#ifdef CHARDONNAY_SHORTCUT_TESTING
#include "WineMacShortcutProbe.h"
#endif
#endif
