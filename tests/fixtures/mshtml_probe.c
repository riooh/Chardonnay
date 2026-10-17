// SPDX-License-Identifier: MIT
// Exercise actual Wine MSHTML/Gecko embedding and DOM readback, not EA removal.
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define COBJMACROS
#include <windows.h>
#include <ole2.h>
#include <oleauto.h>
#include <initguid.h>
#include <mshtml.h>
#include <stdio.h>
#include <wchar.h>

int WINAPI wWinMain(HINSTANCE instance,HINSTANCE previous,PWSTR command,int show){
    (void)instance;(void)previous;(void)command;(void)show;
    HRESULT hr=CoInitialize(NULL);if(FAILED(hr))return 1;
    IHTMLDocument2 *document=NULL;IPersistStreamInit *persist=NULL;IHTMLElement *body=NULL;BSTR text=NULL;
    hr=CoCreateInstance(&CLSID_HTMLDocument,NULL,CLSCTX_INPROC_SERVER,&IID_IHTMLDocument2,(void **)&document);
    if(SUCCEEDED(hr))hr=IHTMLDocument2_QueryInterface(document,&IID_IPersistStreamInit,(void **)&persist);
    if(SUCCEEDED(hr))hr=IPersistStreamInit_InitNew(persist);
    SAFEARRAY *array=SafeArrayCreateVector(VT_VARIANT,0,1);VARIANT *entry=NULL;
    if(!array)return 2;
    SafeArrayAccessData(array,(void **)&entry);VariantInit(entry);entry->vt=VT_BSTR;entry->bstrVal=SysAllocString(L"<html><body>Chardonnay Gecko DOM ready</body></html>");SafeArrayUnaccessData(array);
    if(SUCCEEDED(hr))hr=IHTMLDocument2_write(document,array);
    if(SUCCEEDED(hr))hr=IHTMLDocument2_close(document);
    SafeArrayDestroy(array);
    DWORD deadline=GetTickCount()+5000;
    while(SUCCEEDED(hr) && GetTickCount()<deadline){
        MSG message;while(PeekMessageW(&message,NULL,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}
        if(!body)IHTMLDocument2_get_body(document,&body);
        if(body){if(text){SysFreeString(text);text=NULL;}IHTMLElement_get_innerText(body,&text);if(text && wcsstr(text,L"Chardonnay Gecko DOM ready"))break;}
        Sleep(20);
    }
    HMODULE xul=GetModuleHandleW(L"xul.dll");wchar_t xulPath[4096]=L"missing";
    if(xul)GetModuleFileNameW(xul,xulPath,4096);
    BOOL ok=SUCCEEDED(hr) && xul && text && wcsstr(text,L"Chardonnay Gecko DOM ready");
    wchar_t outputPath[4096];
    if(!GetEnvironmentVariableW(L"CHARDONNAY_GECKO_REPORT",outputPath,4096))swprintf(outputPath,4096,L"C:\\ChardonnayGecko-%u.txt",(unsigned)(sizeof(void *)*8));
    FILE *output=_wfopen(outputPath,L"wb");
    if(output){char utf8[16384];int length=WideCharToMultiByte(CP_UTF8,0,xulPath,-1,utf8,sizeof(utf8),NULL,NULL);fprintf(output,"passed=%u\narchitecture=%u\nhresult=%08lx\nxul=",(unsigned)ok,(unsigned)(sizeof(void *)*8),(unsigned long)hr);if(length>0)fwrite(utf8,1,(size_t)length-1,output);fprintf(output,"\n");fclose(output);}
    if(text)SysFreeString(text);
    if(body)IHTMLElement_Release(body);
    if(persist)IPersistStreamInit_Release(persist);
    if(document)IHTMLDocument2_Release(document);
    CoUninitialize();return ok?0:3;
}
