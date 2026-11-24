#include "rt_gc.h"

#include <stdio.h>
#include <string.h>

static const rt_type TEST_TYPE = { "test_gc_stack", 32, NULL, NULL };

static void allocate_dropped(void) {
    for (int i = 0; i < 64; i++) {
        void *p = rt_gc_new_size(&TEST_TYPE, 32);
        if (p == NULL) {
            fprintf(stderr, "allocate_dropped: allocation failed\n");
            return;
        }
        ((unsigned char *)p)[sizeof(rt_header)] = (unsigned char)i;
    }
}

int main(void) {
    rt_gc_set_stack_scan_enabled(1);
    rt_object *volatile keep = rt_gc_new_size(&TEST_TYPE, 32);
    if (keep == NULL) {
        fprintf(stderr, "test_gc_stack: keep allocation failed\n");
        return 1;
    }
    ((unsigned char *)keep)[sizeof(rt_header)] = 42;
    allocate_dropped();
    size_t before = rt_gc_live();
    size_t freed = rt_gc_collect();
    size_t after = rt_gc_live();
    if (keep->hdr.terminated) {
        fprintf(stderr, "test_gc_stack: live local was collected\n");
        return 1;
    }
    if (((unsigned char *)keep)[sizeof(rt_header)] != 42) {
        fprintf(stderr, "test_gc_stack: payload changed\n");
        return 1;
    }
    if (freed == 0 || after >= before) {
        fprintf(stderr, "test_gc_stack: dropped objects were not reclaimed (before=%zu after=%zu freed=%zu)\n",
                before, after, freed);
        return 1;
    }
    for (int i = 0; i < 3; i++) {
        rt_gc_collect();
        if (keep->hdr.terminated) {
            fprintf(stderr, "test_gc_stack: local collected on repeat %d\n", i);
            return 1;
        }
    }
    printf("test_gc_stack: PASS (before=%zu after=%zu freed=%zu)\n", before, after, freed);
    return 0;
}
