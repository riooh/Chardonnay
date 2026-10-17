// SPDX-License-Identifier: MIT
// Private Win32 GUI acceptance fixture: installs one shortcut, then stays open.
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <shlobj.h>
#include <objbase.h>
#include <stdio.h>

static LRESULT CALLBACK window_proc(HWND window,UINT message,WPARAM wparam,LPARAM lparam){
    if(message==WM_APP+1){
        FILE *output=_wfopen(L"C:\\ChardonnayRuntime-launch.txt",L"a");
        if(!output){PostQuitMessage(4);return 0;}
        fprintf(output,"launch=%lu\n",(unsigned long)GetCurrentProcessId());fclose(output);return 0;
    }
    if(message==WM_CLOSE){DestroyWindow(window);return 0;}
    if(message==WM_DESTROY){PostQuitMessage(0);return 0;}
    return DefWindowProcW(window,message,wparam,lparam);
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,LPWSTR args,int show){
    (void)previous;(void)show;
    if(wcsstr(args,L"--run")){
        WNDCLASSW cls={0};cls.lpfnWndProc=window_proc;cls.hInstance=instance;cls.lpszClassName=L"ChardonnayRuntimeFixture";
        if(!RegisterClassW(&cls))return 2;
        HWND window=CreateWindowW(cls.lpszClassName,L"Private Runtime Fixture",WS_OVERLAPPEDWINDOW|WS_VISIBLE,CW_USEDEFAULT,CW_USEDEFAULT,460,240,NULL,NULL,instance,NULL);
        if(!window)return 3;
        PostMessageW(window,WM_APP+1,0,0);
        MSG message;while(GetMessageW(&message,NULL,0,0)>0){TranslateMessage(&message);DispatchMessageW(&message);}return 0;
    }
    wchar_t source[MAX_PATH],directory[MAX_PATH],target[MAX_PATH],programs[MAX_PATH],link_path[MAX_PATH];
    if(!GetModuleFileNameW(NULL,source,MAX_PATH))return 5;
    if(FAILED(SHGetFolderPathW(NULL,CSIDL_PROGRAM_FILES,NULL,0,directory)))return 6;
    wcscat(directory,L"\\Chardonnay Runtime Fixture");CreateDirectoryW(directory,NULL);
    swprintf(target,MAX_PATH,L"%ls\\RuntimeFixture.exe",directory);if(!CopyFileW(source,target,FALSE))return 7;
    if(FAILED(SHGetFolderPathW(NULL,CSIDL_PROGRAMS,NULL,0,programs)))return 8;
    swprintf(link_path,MAX_PATH,L"%ls\\Runtime Fixture.lnk",programs);
    if(FAILED(CoInitialize(NULL)))return 9;
    IShellLinkW *link=NULL;IPersistFile *persist=NULL;HRESULT result=CoCreateInstance(&CLSID_ShellLink,NULL,CLSCTX_INPROC_SERVER,&IID_IShellLinkW,(void **)&link);
    if(SUCCEEDED(result))result=link->lpVtbl->SetPath(link,target);
    if(SUCCEEDED(result))result=link->lpVtbl->SetArguments(link,L"--run");
    if(SUCCEEDED(result))result=link->lpVtbl->SetWorkingDirectory(link,directory);
    if(SUCCEEDED(result))result=link->lpVtbl->QueryInterface(link,&IID_IPersistFile,(void **)&persist);
    if(SUCCEEDED(result))result=persist->lpVtbl->Save(persist,link_path,TRUE);
    if(persist)persist->lpVtbl->Release(persist);
    if(link)link->lpVtbl->Release(link);
    CoUninitialize();return FAILED(result)?10:0;
}
