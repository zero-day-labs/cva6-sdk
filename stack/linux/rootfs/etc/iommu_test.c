#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#define PAGE_SIZE 0x1000ULL

int main(int argc, char* argv[])
{
    int fd, ret;
    char buf[8192] __attribute__((aligned(PAGE_SIZE)));
    char *src_ptr = NULL, *dst_ptr = NULL;

    // Check N of arguments
    if (argc != 2)
    {
        printf("Wrong number of arguments!\nProvide a short word to transfer (e.g. 'hello_world')\n");
        exit(1);
    }

    // Check word length
    if (strlen(argv[1]) >= 30)
    {
        printf("The provided word is too long. Please introduce a shorter word (30 chars max)\n");
        exit(1);
    }

    // Open dev file
    fd = open("/dev/idma0", O_RDWR);
    if (fd < 0) {
        perror("Could not open iDMA dev file\n");
        exit(1);
    }

    // Init transfer
    src_ptr = buf;
    dst_ptr = &buf[4096];
    strcpy(src_ptr,argv[1]);
    ret = write(fd, buf, strlen(argv[1]));
    
    if (ret < 0)
    {
        perror("Could not write to iDMA\n");
        exit(1);
    }

    // Print results
    printf("Src: %s | Dst: %s\n", src_ptr, dst_ptr);

    close(fd);

    return 0;
}
