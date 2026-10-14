#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
#include <stdint.h>

static int fail(const char *step, HRESULT hr) { printf("FAIL %s hr=0x%08lx\n",step,(unsigned long)hr); return 2; }
int main(void) {
    ID3D11Device *producer=NULL,*consumer=NULL;
    ID3D11DeviceContext *pc=NULL,*cc=NULL;
    ID3D11Texture2D *tex=NULL,*opened=NULL,*stage=NULL;
    IDXGIResource *resource=NULL; ID3D11RenderTargetView *rtv=NULL;
    D3D_FEATURE_LEVEL requested=D3D_FEATURE_LEVEL_11_0,level;
    HRESULT hr=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,D3D11_CREATE_DEVICE_BGRA_SUPPORT,&requested,1,D3D11_SDK_VERSION,&producer,&level,&pc);
    printf("producer device hr=0x%08lx level=0x%x\n",(unsigned long)hr,level); fflush(stdout);
    if(FAILED(hr))return fail("producer device",hr);
    D3D11_TEXTURE2D_DESC desc={0};desc.Width=32;desc.Height=32;desc.MipLevels=1;desc.ArraySize=1;desc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;desc.SampleDesc.Count=1;desc.Usage=D3D11_USAGE_DEFAULT;desc.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;desc.MiscFlags=D3D11_RESOURCE_MISC_SHARED;
    hr=ID3D11Device_CreateTexture2D(producer,&desc,NULL,&tex);if(FAILED(hr))return fail("shared texture",hr);
    hr=ID3D11Texture2D_QueryInterface(tex,&IID_IDXGIResource,(void**)&resource);if(FAILED(hr))return fail("IDXGIResource",hr);
    HANDLE handle=NULL;hr=IDXGIResource_GetSharedHandle(resource,&handle);
    printf("GetSharedHandle hr=0x%08lx handle=%p\n",(unsigned long)hr,handle);fflush(stdout);
    if(FAILED(hr)||!handle)return fail("GetSharedHandle",hr);
    /* Regression: Metal cube arrayLength counts cubes, but view slices count
       faces. The class-wide sharing swizzle must preserve all six faces. */
    D3D11_TEXTURE2D_DESC cube_desc=desc;cube_desc.Width=16;cube_desc.Height=16;cube_desc.ArraySize=6;cube_desc.BindFlags=D3D11_BIND_SHADER_RESOURCE;cube_desc.MiscFlags=D3D11_RESOURCE_MISC_TEXTURECUBE;
    ID3D11Texture2D *cube=NULL;ID3D11ShaderResourceView *cube_view=NULL;
    hr=ID3D11Device_CreateTexture2D(producer,&cube_desc,NULL,&cube);if(FAILED(hr))return fail("cube texture",hr);
    D3D11_SHADER_RESOURCE_VIEW_DESC srv={0};srv.Format=cube_desc.Format;srv.ViewDimension=D3D11_SRV_DIMENSION_TEXTURECUBE;srv.TextureCube.MipLevels=1;
    printf("Creating six-face cube view after sharing hooks\n");fflush(stdout);
    hr=ID3D11Device_CreateShaderResourceView(producer,(ID3D11Resource*)cube,&srv,&cube_view);if(FAILED(hr))return fail("cube shader view",hr);
    ID3D11ShaderResourceView_Release(cube_view);ID3D11Texture2D_Release(cube);printf("CUBE VIEW REGRESSION: PASS\n");fflush(stdout);
    hr=ID3D11Device_CreateRenderTargetView(producer,(ID3D11Resource*)tex,NULL,&rtv);if(FAILED(hr))return fail("render target",hr);
    const float red[4]={1,0,0,1};ID3D11DeviceContext_ClearRenderTargetView(pc,rtv,red);
    /* Flush only submits work; cross-device visibility needs GPU completion. */
    D3D11_QUERY_DESC qdesc={D3D11_QUERY_EVENT,0};ID3D11Query *done=NULL;
    hr=ID3D11Device_CreateQuery(producer,&qdesc,&done);if(FAILED(hr))return fail("producer completion query",hr);
    ID3D11DeviceContext_End(pc,(ID3D11Asynchronous*)done);ID3D11DeviceContext_Flush(pc);
    BOOL finished=FALSE;DWORD started=GetTickCount();
    do {hr=ID3D11DeviceContext_GetData(pc,(ID3D11Asynchronous*)done,&finished,sizeof(finished),0);if(FAILED(hr))return fail("producer completion",hr);if(hr==S_OK&&finished)break;Sleep(1);}while(GetTickCount()-started<10000);
    ID3D11Query_Release(done);if(hr!=S_OK||!finished)return fail("producer completion timeout",E_FAIL);
    printf("producer GPU completion confirmed\n");fflush(stdout);
    hr=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,D3D11_CREATE_DEVICE_BGRA_SUPPORT,&requested,1,D3D11_SDK_VERSION,&consumer,&level,&cc);if(FAILED(hr))return fail("consumer device",hr);
    hr=ID3D11Device_OpenSharedResource(consumer,handle,&IID_ID3D11Texture2D,(void**)&opened);printf("OpenSharedResource hr=0x%08lx\n",(unsigned long)hr);fflush(stdout);if(FAILED(hr))return fail("OpenSharedResource",hr);
    desc.Usage=D3D11_USAGE_STAGING;desc.BindFlags=0;desc.MiscFlags=0;desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ;
    hr=ID3D11Device_CreateTexture2D(consumer,&desc,NULL,&stage);if(FAILED(hr))return fail("staging texture",hr);
    ID3D11DeviceContext_CopyResource(cc,(ID3D11Resource*)stage,(ID3D11Resource*)opened);
    D3D11_MAPPED_SUBRESOURCE mapped;hr=ID3D11DeviceContext_Map(cc,(ID3D11Resource*)stage,0,D3D11_MAP_READ,0,&mapped);if(FAILED(hr))return fail("readback Map",hr);
    unsigned char *p=(unsigned char*)mapped.pData;printf("READBACK BGRA=%u,%u,%u,%u row_pitch=%u\n",p[0],p[1],p[2],p[3],mapped.RowPitch);
    int ok=p[0]==0&&p[1]==0&&p[2]==255&&p[3]==255;ID3D11DeviceContext_Unmap(cc,(ID3D11Resource*)stage,0);
    ID3D11Texture2D_Release(stage);ID3D11Texture2D_Release(opened);ID3D11RenderTargetView_Release(rtv);IDXGIResource_Release(resource);ID3D11Texture2D_Release(tex);ID3D11DeviceContext_Release(cc);ID3D11Device_Release(consumer);ID3D11DeviceContext_Release(pc);ID3D11Device_Release(producer);
    printf("WINE SAME-PROCESS SHARING: %s\n",ok?"PASS":"FAIL");return ok?0:3;
}
