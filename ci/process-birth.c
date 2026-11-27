// Host-side measurement only. Never linked into the iOS app.
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/proc_info.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    struct proc_bsdinfo info = {0};
    if (proc_pidinfo(atoi(argv[1]), PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return 1;
    printf("%.6f\n", (double)info.pbi_start_tvsec + (double)info.pbi_start_tvusec / 1000000.0);
    return 0;
}
