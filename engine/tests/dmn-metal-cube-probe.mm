#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "src/dmn_share.h"
#include <cstdio>
#include <cstring>
#include <unistd.h>

int main(int argc,char **argv) {
 @autoreleasepool {
  bool hooks=!(argc>1&&!strcmp(argv[1],"--no-hooks"));
  if(hooks)dmn_share_install_swizzles();
  id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 2;
  id<MTLTexture> shared=nil;
  if(hooks){
   MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:32 height:32 mipmapped:NO];
   d.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
   dmn_share_arm_producer(0);shared=[device newTextureWithDescriptor:d];DmnShareArm arm={};
   if(!dmn_share_disarm(&arm)||!shared)return 3;
   if(arm.out_fd>=0)close(arm.out_fd);
  }
  struct Case {MTLTextureType type;NSUInteger arrays,first,count;const char *name;};
  Case cases[]={{MTLTextureTypeCube,1,0,6,"cube"},{MTLTextureTypeCubeArray,2,0,12,"cube-array"},{MTLTextureTypeCubeArray,2,6,6,"second-cube"},{MTLTextureType2DArray,3,0,3,"2d-array"}};
  for(auto c:cases){
   MTLTextureDescriptor *d=[MTLTextureDescriptor new];d.textureType=c.type;d.pixelFormat=MTLPixelFormatBGRA8Unorm;d.width=16;d.height=16;d.mipmapLevelCount=1;d.arrayLength=c.arrays;d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageShaderRead|MTLTextureUsagePixelFormatView;
   id<MTLTexture> t=[device newTextureWithDescriptor:d];if(!t)return 4;
   printf("VIEW %s source_type=%lu arrayLength=%lu slices=%lu,+%lu hooks=%d\n",c.name,(unsigned long)t.textureType,(unsigned long)t.arrayLength,(unsigned long)c.first,(unsigned long)c.count,hooks);fflush(stdout);
   MTLTextureType viewtype=c.type;if(!strcmp(c.name,"second-cube"))viewtype=MTLTextureTypeCube;
   id<MTLTexture> v=[t newTextureViewWithPixelFormat:t.pixelFormat textureType:viewtype levels:NSMakeRange(0,1) slices:NSMakeRange(c.first,c.count) swizzle:MTLTextureSwizzleChannelsMake(MTLTextureSwizzleRed,MTLTextureSwizzleGreen,MTLTextureSwizzleBlue,MTLTextureSwizzleAlpha)];
   if(!v)return 5;printf("PASS %s view_type=%lu arrayLength=%lu\n",c.name,(unsigned long)v.textureType,(unsigned long)v.arrayLength);
  }
  printf("METAL CUBE-VIEW REGRESSION: PASS\n");return 0;
 }
}
