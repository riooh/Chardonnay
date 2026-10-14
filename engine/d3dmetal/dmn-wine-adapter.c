/* Experimental Wine host adapter. Keeps Apple's existing Wine GFXT host;
 * installs only d3dmetal-native's device/resource hooks, never dmn_init().
 * ABI pinned to the inspected CX bridge: two Unix calls and 0x160-byte table.
 * This spike supports same-process sharing only; native POD handles are NOT
 * valid Wine cross-process/NT handles. Do not deploy as a general backend. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <dlfcn.h>
#include <pthread.h>

#define MSABI __attribute__((ms_abi))
typedef int32_t (*unixcall_t)(void *);
typedef int32_t (MSABI *create_t)(void*,uint32_t,void*,uint32_t,const uint32_t*,uint32_t,uint32_t,void**,uint32_t*,void**);
typedef int32_t (MSABI *create_swap_t)(void*,uint32_t,void*,uint32_t,const uint32_t*,uint32_t,uint32_t,const void*,void**,void**,uint32_t*,void**);
static unixcall_t *original;
static void (*after_device)(void*);
static create_t real_create;
static create_swap_t real_create_swap;
static pthread_once_t once=PTHREAD_ONCE_INIT;

static void fatal(const char *msg) { fprintf(stderr,"[dmn-wine] FATAL %s: %s\n",msg,dlerror()); abort(); }
static void load_adapter(void) {
    Dl_info info;char dir[PATH_MAX],path[PATH_MAX];
    if(!dladdr((void*)load_adapter,&info)||!info.dli_fname)fatal("locate adapter");
    if(snprintf(dir,sizeof(dir),"%s",info.dli_fname)>=(int)sizeof(dir))fatal("adapter path too long");
    char *slash=strrchr(dir,'/');if(!slash)fatal("adapter directory");*slash=0;
    if(snprintf(path,sizeof(path),"%s/libd3dmetal-native.dylib",dir)>=(int)sizeof(path))fatal("native path too long");
    void *native=dlopen(path,RTLD_NOW|RTLD_LOCAL);if(!native)fatal("load native hooks");
    void (*swizzle)(void)=dlsym(native,"dmn_share_install_swizzles");
    after_device=dlsym(native,"dmn_hooks_after_d3d11_device");
    if(!swizzle||!after_device)fatal("resolve native hooks");
    swizzle();
    if(snprintf(path,sizeof(path),"%s/libd3dshared.dylib",dir)>=(int)sizeof(path))fatal("original path too long");
    void *apple=dlopen(path,RTLD_NOW|RTLD_LOCAL);if(!apple)fatal("load original Wine host");
    original=dlsym(apple,"__wine_unix_call_funcs");if(!original)fatal("resolve original Unix calls");
    fprintf(stderr,"[dmn-wine] hook library loaded; original Wine host preserved\n");
}
static int32_t MSABI hooked_create(void *a,uint32_t t,void *s,uint32_t flags,const uint32_t *levels,uint32_t count,uint32_t sdk,void **device,uint32_t *level,void **context) {
    int32_t hr=real_create(a,t,s,flags,levels,count,sdk,device,level,context);
    if(hr>=0&&device&&*device){after_device(*device);fprintf(stderr,"[dmn-wine] patched D3D11 device %p\n",*device);}
    return hr;
}
static int32_t MSABI hooked_create_swap(void *a,uint32_t t,void *s,uint32_t flags,const uint32_t *levels,uint32_t count,uint32_t sdk,const void *desc,void **swap,void **device,uint32_t *level,void **context) {
    int32_t hr=real_create_swap(a,t,s,flags,levels,count,sdk,desc,swap,device,level,context);
    if(hr>=0&&device&&*device){after_device(*device);fprintf(stderr,"[dmn-wine] patched D3D11 swapchain device %p\n",*device);}
    return hr;
}
static int32_t bridge_init(void *args) {
    pthread_once(&once,load_adapter);
    int32_t hr=original[0](args);if(hr<0)return hr;
    void **table=args;Dl_info fn;
    if(!table[7]||!table[8]||!dladdr(table[7],&fn)||!fn.dli_sname||!strstr(fn.dli_sname,"Shared_D3D11CreateDevice"))fatal("unexpected dispatch table ABI");
    real_create=(create_t)table[7];real_create_swap=(create_swap_t)table[8];
    table[7]=(void*)hooked_create;table[8]=(void*)hooked_create_swap;
    fprintf(stderr,"[dmn-wine] installed D3D11 factory hooks in Wine dispatch table\n");return hr;
}
static int32_t bridge_win32(void *args) {pthread_once(&once,load_adapter);return original[1](args);}
__attribute__((visibility("default"))) const unixcall_t __wine_unix_call_funcs[]={bridge_init,bridge_win32};
