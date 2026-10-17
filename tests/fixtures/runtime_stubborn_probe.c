// SPDX-License-Identifier: MIT
// Deliberately uncooperative NATIVE fixture, not a Windows/Wine compatibility test.
// Its private executable must be named 'wine' for the native candidate filter.
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc,char **argv){
    if(argc!=3 || !strstr(argv[1],"/.wine-") || !strstr(argv[1],"/server-") || !strstr(argv[2],"ChardonnayRuntime-stubborn.txt"))return 2;
    struct stat directory;if(lstat(argv[1],&directory) || !S_ISDIR(directory.st_mode) || directory.st_uid!=getuid())return 3;
    char file[4096];if(snprintf(file,sizeof(file),"%s/tmpmap-chardonnay-private-%d",argv[1],getpid())>=(int)sizeof(file))return 4;
    int descriptor=open(file,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW,0600);if(descriptor<0)return 5;
    if(ftruncate(descriptor,4096))return 6;
    void *memory=mmap(NULL,4096,PROT_READ|PROT_WRITE,MAP_SHARED,descriptor,0);if(memory==MAP_FAILED)return 7;
    // Unlink now: the owned mapping remains visible through lsof, without a
    // persistent test file in the runtime namespace after a deliberate KILL.
    unlink(file);close(descriptor);memset(memory,0,4096);
    signal(SIGTERM,SIG_IGN);
    FILE *ready=fopen(argv[2],"wx");if(!ready)return 8;fprintf(ready,"pid=%d\n",getpid());fclose(ready);
    for(;;)pause();
}
