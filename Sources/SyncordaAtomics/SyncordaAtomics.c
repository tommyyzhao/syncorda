#include "SyncordaAtomics.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct SyncordaAtomicUInt64 {
    _Atomic(uint64_t) value;
};

SyncordaAtomicUInt64 *syncorda_atomic_u64_create(uint64_t initialValue) {
    SyncordaAtomicUInt64 *result = calloc(1, sizeof(SyncordaAtomicUInt64));
    if (result != NULL) {
        atomic_init(&result->value, initialValue);
    }
    return result;
}

void syncorda_atomic_u64_destroy(SyncordaAtomicUInt64 *atomicValue) {
    free(atomicValue);
}

uint64_t syncorda_atomic_u64_load(const SyncordaAtomicUInt64 *atomicValue) {
    return atomic_load_explicit(&atomicValue->value, memory_order_acquire);
}

void syncorda_atomic_u64_store(SyncordaAtomicUInt64 *atomicValue, uint64_t value) {
    atomic_store_explicit(&atomicValue->value, value, memory_order_release);
}

uint64_t syncorda_atomic_u64_add(SyncordaAtomicUInt64 *atomicValue, uint64_t value) {
    return atomic_fetch_add_explicit(&atomicValue->value, value, memory_order_relaxed) + value;
}

int syncorda_unix_socket_address(const char *path, struct sockaddr_un *address, socklen_t *length) {
    const size_t path_length = strlen(path);
    if (path_length >= sizeof(address->sun_path)) {
        return 0;
    }
    memset(address, 0, sizeof(*address));
    address->sun_family = AF_UNIX;
    memcpy(address->sun_path, path, path_length + 1);
    *length = (socklen_t)sizeof(*address);
    return 1;
}
