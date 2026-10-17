/* SPDX-License-Identifier: MIT */
#define _WIN32_WINNT 0x0601
#define COBJMACROS
#include <windows.h>
#include <shobjidl.h>
#include <stdio.h>
#include <wchar.h>

static HWND edit;
static wchar_t output[MAX_PATH*4], test_case[64];
static DWORD start;
static int queried, closed, ended, veto;
static WNDPROC old_edit_proc;
static void report(const char *event, int passed);

static LRESULT CALLBACK edit_proc(HWND window,UINT message,WPARAM wp,LPARAM lp)
{
    if(message==WM_COPY||message==WM_CUT||message==WM_PASTE)
    {
        // Native Edit menus may send control messages rather than accelerators.
        // Acknowledge the action before EDIT's default procedure touches clipboard.
        report(message==WM_COPY?"copy-key":message==WM_PASTE?"paste-key":"cut-key",1);
        DestroyWindow(GetParent(window));return 0;
    }
    return CallWindowProcW(old_edit_proc,window,message,wp,lp);
}

static void report(const char *event, int passed)
{
    FILE *file=_wfopen(output,L"ab");
    if (!file) return;
    fprintf(file,"event=%s passed=%d query=%d close=%d end=%d iconic=%d ctrl=%d async_ctrl=%d alt=%d\n",
        event,passed,queried,closed,ended,IsIconic(GetParent(edit))!=0,
        (GetKeyState(VK_CONTROL)&0x8000)!=0,(GetAsyncKeyState(VK_CONTROL)&0x8000)!=0,
        (GetKeyState(VK_MENU)&0x8000)!=0);
    fclose(file);
}

static LRESULT CALLBACK window_proc(HWND window,UINT message,WPARAM wp,LPARAM lp)
{
    switch(message)
    {
    case WM_CREATE:
        edit=CreateWindowW(L"EDIT",L"base",WS_CHILD|WS_VISIBLE|ES_MULTILINE|WS_BORDER,
            10,10,340,120,window,(HMENU)(INT_PTR)1,GetModuleHandleW(NULL),NULL);
        old_edit_proc=(WNDPROC)SetWindowLongPtrW(edit,GWLP_WNDPROC,(LONG_PTR)edit_proc);
        SendMessageW(edit,EM_SETSEL,0,-1);
        SendMessageW(edit,EM_REPLACESEL,TRUE,(LPARAM)L"edited");
        SetTimer(window,1,100,NULL);
        return 0;
    case WM_COMMAND:
        if (LOWORD(wp)==101) SendMessageW(edit,EM_SETSEL,0,-1);
        else if (LOWORD(wp)==102) SendMessageW(edit,EM_UNDO,0,0);
        else if (LOWORD(wp)>=103 && LOWORD(wp)<=105)
        {
            // Acknowledge accelerator delivery without touching the user's clipboard.
            report(LOWORD(wp)==103?"copy-key":LOWORD(wp)==104?"paste-key":"cut-key",1);
            DestroyWindow(window);
        }
        return 0;
    case WM_QUERYENDSESSION:
        queried++;report(veto?"quit-veto":"quit-query",veto?1:0);return !veto;
    case WM_ENDSESSION:
        if(wp){ended++;report("quit-ended",1);DestroyWindow(window);}
        return 0;
    case WM_CLOSE:
        closed++;
        if(veto){report("close-veto",1);return 0;}
        report("close",1);DestroyWindow(window);return 0;
    case WM_TIMER:
    {
        DWORD first=0,last=0;
        wchar_t text[128];
        int passed=0;
        const char *event="";
        if (!wcscmp(test_case,L"production-smoke")&&GetTickCount()-start>2500)
        {passed=IsWindow(window)&&IsWindowVisible(window);event="production-smoke";}
        else if (!wcscmp(test_case,L"minimize")&&IsIconic(window)){passed=1;event="minimize";}
        else if ((!wcscmp(test_case,L"hide")||!wcscmp(test_case,L"fullscreen")) && GetTickCount()-start>3000)
        {passed=1;event="native-state-check";}
        else if (veto&&(queried||closed)&&GetTickCount()-start>2500)
        {passed=IsWindow(window)&&!ended;event="veto-survived";}
        else if (!wcscmp(test_case,L"select-all")||!wcscmp(test_case,L"control-a"))
        {
            SendMessageW(edit,EM_GETSEL,(WPARAM)&first,(LPARAM)&last);
            if(first==0&&last==6){passed=1;event="selected-all";}
        }
        else if (!wcscmp(test_case,L"undo"))
        {
            GetWindowTextW(edit,text,128);
            if(!wcscmp(text,L"base")){passed=1;event="undo";}
        }
        if(passed){report(event,1);DestroyWindow(window);}
        else if(GetTickCount()-start>15000){report("timeout",0);DestroyWindow(window);}
        return 0;
    }
    case WM_DESTROY:PostQuitMessage(0);return 0;
    default:return DefWindowProcW(window,message,wp,lp);
    }
}

int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,LPWSTR command,int show)
{
    WNDCLASSW klass={0};MSG message;HWND window;HACCEL accelerator;
    ACCEL keys[]={{FVIRTKEY|FCONTROL,'A',101},{FVIRTKEY|FCONTROL,'Z',102},
        {FVIRTKEY|FCONTROL,'C',103},{FVIRTKEY|FCONTROL,'V',104},{FVIRTKEY|FCONTROL,'X',105}};
    (void)previous;(void)command;(void)show;
    GetEnvironmentVariableW(L"CHARDONNAY_SHORTCUT_WIN_REPORT",output,MAX_PATH*4);
    GetEnvironmentVariableW(L"CHARDONNAY_SHORTCUT_CASE",test_case,64);
    veto=wcsstr(test_case,L"veto")!=NULL;
    SetCurrentProcessExplicitAppUserModelID(L"local.chardonnay.private-shortcut-fixture");
    klass.lpfnWndProc=window_proc;klass.hInstance=instance;klass.lpszClassName=L"ChardonnayShortcutFixture";
    klass.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);klass.hCursor=LoadCursorW(NULL,IDC_ARROW);
    if(!RegisterClassW(&klass))return 2;
    start=GetTickCount();
    window=CreateWindowW(klass.lpszClassName,L"Chardonnay Shortcut Fixture",WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,CW_USEDEFAULT,390,210,NULL,NULL,instance,NULL);
    if(!window)return 3;
    ShowWindow(window,SW_SHOW);SetForegroundWindow(window);SetFocus(edit);
    // Do not start with a selected-all range: the shortcut must produce it.
    SendMessageW(edit,EM_SETSEL,6,6);
    accelerator=CreateAcceleratorTableW(keys,sizeof(keys)/sizeof(keys[0]));
    report("ready",0);
    while(GetMessageW(&message,NULL,0,0)>0)
        if(!TranslateAcceleratorW(window,accelerator,&message))
        {TranslateMessage(&message);DispatchMessageW(&message);}
    DestroyAcceleratorTable(accelerator);
    return 0;
}
