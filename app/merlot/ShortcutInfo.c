/* MIT: read shell-link metadata without executing it, and set a private
 * Desktop import folder through Wine's live registry (never edit user.reg). */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <stdio.h>
#include <wchar.h>

static void json_string(const wchar_t *value) {
 int n=WideCharToMultiByte(CP_UTF8,0,value,-1,NULL,0,NULL,NULL);
 char *b=HeapAlloc(GetProcessHeap(),0,(SIZE_T)n);if(!b){fputs("null",stdout);return;}
 WideCharToMultiByte(CP_UTF8,0,value,-1,b,n,NULL,NULL);putchar('"');
 for(int i=0;i<n-1;i++){unsigned char c=(unsigned char)b[i];if(c=='"'||c=='\\'){putchar('\\');putchar(c);}else if(c<32)printf("\\u%04x",c);else putchar(c);}
 putchar('"');HeapFree(GetProcessHeap(),0,b);
}
static int desktop_setup(void) {
 wchar_t path[32768];DWORD n=GetEnvironmentVariableW(L"USERPROFILE",path,32000);
 if(!n||n>=32000)return 2;
 wcscat(path,L"\\Wine Shortcuts");
 int r=SHCreateDirectoryExW(NULL,path,NULL);if(r!=ERROR_SUCCESS&&r!=ERROR_ALREADY_EXISTS&&r!=ERROR_FILE_EXISTS)return 3;
 const wchar_t *keys[]={L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders",L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders"};
 for(int i=0;i<2;i++){HKEY k;if(RegCreateKeyExW(HKEY_CURRENT_USER,keys[i],0,NULL,0,KEY_SET_VALUE,NULL,&k,NULL)!=ERROR_SUCCESS)return 4;
  LONG e=RegSetValueExW(k,L"Desktop",0,i?REG_EXPAND_SZ:REG_SZ,(BYTE*)path,(DWORD)((wcslen(path)+1)*sizeof(wchar_t)));RegCloseKey(k);if(e!=ERROR_SUCCESS)return 5;}
 DWORD_PTR ignored;SendMessageTimeoutW(HWND_BROADCAST,WM_SETTINGCHANGE,0,(LPARAM)L"Shell Folders",SMTO_ABORTIFHUNG,500,&ignored);
 printf("{\"desktop\":");json_string(path);puts("}");return 0;
}
int wmain(int argc,wchar_t **argv) {
 if(argc!=2)return 1;
 if(!wcscmp(argv[1],L"--setup-desktop"))return desktop_setup();
 HRESULT hr=CoInitializeEx(NULL,COINIT_APARTMENTTHREADED);if(FAILED(hr))return 2;
 IShellLinkW *link=NULL;IPersistFile *file=NULL;
 hr=CoCreateInstance(&CLSID_ShellLink,NULL,CLSCTX_INPROC_SERVER,&IID_IShellLinkW,(void**)&link);if(FAILED(hr))return 3;
 hr=IShellLinkW_QueryInterface(link,&IID_IPersistFile,(void**)&file);if(FAILED(hr))return 4;
 hr=IPersistFile_Load(file,argv[1],STGM_READ);if(FAILED(hr))return 5;
 wchar_t target[32768]={0},args[32768]={0},cwd[32768]={0},icon[32768]={0};int index=0;
 IShellLinkW_GetPath(link,target,32768,NULL,SLGP_RAWPATH);IShellLinkW_GetArguments(link,args,32768);IShellLinkW_GetWorkingDirectory(link,cwd,32768);IShellLinkW_GetIconLocation(link,icon,32768,&index);
 fputs("{\"target\":",stdout);json_string(target);fputs(",\"arguments\":",stdout);json_string(args);fputs(",\"working_dir\":",stdout);json_string(cwd);fputs(",\"icon\":",stdout);json_string(icon);printf(",\"icon_index\":%d}\n",index);
 IPersistFile_Release(file);IShellLinkW_Release(link);CoUninitialize();return 0;
}
