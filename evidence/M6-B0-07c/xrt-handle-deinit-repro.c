#include "xrt.h"
#include <stdio.h>
int main(void) {
    xrt_handle *h = xrt_handle_new((void *)1, NULL, "t");
    fprintf(stderr, "closed_before=%d\n", xrt_handle_is_closed(h));
    xrt_handle_mark_closed(h);
    fprintf(stderr, "closed_after=%d\n", xrt_handle_is_closed(h));
    xrt_release(h);
    xrt_safepoint();
    fprintf(stderr, "done\n");
    return 0;
}
