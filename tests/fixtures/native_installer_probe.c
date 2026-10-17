// SPDX-License-Identifier: MIT
// Actual Win32 installer/application used only in a private macOS acceptance bottle.
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define COBJMACROS
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <stdio.h>
#include <wchar.h>

static int marker(const wchar_t *path,const wchar_t *text){
    HANDLE file=CreateFileW(path,GENERIC_WRITE,0,NULL,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,NULL);
    if(file==INVALID_HANDLE_VALUE)return 1;
    char buffer[32768];int count=WideCharToMultiByte(CP_UTF8,0,text,-1,buffer,sizeof(buffer),NULL,NULL);DWORD written=0;
    BOOL ok=count>0 && WriteFile(file,buffer,(DWORD)count-1,&written,NULL);
    CloseHandle(file);return ok?0:1;
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,PWSTR command,int show){
    (void)instance;(void)previous;(void)show;
    wchar_t cwd[4096],prefix[4096],text[16000];GetCurrentDirectoryW(4096,cwd);GetEnvironmentVariableW(L"WINEPREFIX",prefix,4096);
    if(wcsstr(command,L"--launch-probe")){
        wchar_t msi[256]=L"missing";DWORD size=sizeof(msi);
        RegGetValueW(HKEY_CURRENT_USER,L"Software\\Chardonnay\\InstallerProbe",L"MSI",RRF_RT_REG_SZ,NULL,msi,&size);
        swprintf(text,16000,L"argv=%ls\ncwd=%ls\nprefix=%ls\nmsi=%ls\n",command,cwd,prefix,msi);
        return marker(L"C:\\ChardonnayFixture-launch.txt",text);
    }
    const wchar_t *directory=L"C:\\Program Files\\Chardonnay Fixture";
    const wchar_t *application=L"C:\\Program Files\\Chardonnay Fixture\\FixtureApp.exe";
    CreateDirectoryW(directory,NULL);wchar_t self[4096];GetModuleFileNameW(NULL,self,4096);
    if(!CopyFileW(self,application,FALSE))return 2;
    wchar_t programs[4096],shortcut[8192];
    if(FAILED(SHGetFolderPathW(NULL,CSIDL_PROGRAMS|CSIDL_FLAG_CREATE,NULL,SHGFP_TYPE_CURRENT,programs)))return 3;
    swprintf(shortcut,8192,L"%ls\\Chardonnay Fixture.lnk",programs);
    HRESULT hr=CoInitialize(NULL);if(FAILED(hr))return 4;
    IShellLinkW *link=NULL;IPersistFile *persist=NULL;
    hr=CoCreateInstance(&CLSID_ShellLink,NULL,CLSCTX_INPROC_SERVER,&IID_IShellLinkW,(void **)&link);
    if(SUCCEEDED(hr))hr=IShellLinkW_SetPath(link,application);
    if(SUCCEEDED(hr))hr=IShellLinkW_SetArguments(link,L"--launch-probe Ω");
    if(SUCCEEDED(hr))hr=IShellLinkW_SetWorkingDirectory(link,directory);
    if(SUCCEEDED(hr))hr=IShellLinkW_QueryInterface(link,&IID_IPersistFile,(void **)&persist);
    if(SUCCEEDED(hr))hr=IPersistFile_Save(persist,shortcut,TRUE);
    if(persist)IPersistFile_Release(persist);
    if(link)IShellLinkW_Release(link);
    CoUninitialize();
    if(FAILED(hr))return 5;
    wchar_t *slash=wcsrchr(self,L'\\');if(!slash)return 6;*slash=0;
    wchar_t builder[8192],msi[8192],builderCommand[20000];
    swprintf(builder,8192,L"%ls\\BuildMsi.exe",self);
    swprintf(msi,8192,L"%ls\\Fixture Ω.msi",self);
    swprintf(builderCommand,20000,L"\"%ls\" \"%ls\"",builder,msi);
    STARTUPINFOW startup={0};startup.cb=sizeof(startup);PROCESS_INFORMATION process={0};
    if(!CreateProcessW(builder,builderCommand,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,self,&startup,&process))return 7;
    WaitForSingleObject(process.hProcess,30000);DWORD code=1;GetExitCodeProcess(process.hProcess,&code);
    CloseHandle(process.hThread);CloseHandle(process.hProcess);
    if(code){swprintf(text,16000,L"msi_builder_exit=%lu\n",code);marker(L"C:\\ChardonnayFixture-builder-exit.txt",text);return 8;}
    swprintf(text,16000,L"installed=EXE\nprefix=%ls\n",prefix);
    return marker(L"C:\\ChardonnayFixture-install.txt",text);
}
