#ifndef SYNCORDA_ATOMICS_H
#define SYNCORDA_ATOMICS_H

#include <stdint.h>
#include <sys/socket.h>
#include <sys/un.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SyncordaAtomicUInt64 SyncordaAtomicUInt64;

SyncordaAtomicUInt64 *syncorda_atomic_u64_create(uint64_t initialValue);
void syncorda_atomic_u64_destroy(SyncordaAtomicUInt64 *atomicValue);
uint64_t syncorda_atomic_u64_load(const SyncordaAtomicUInt64 *atomicValue);
void syncorda_atomic_u64_store(SyncordaAtomicUInt64 *atomicValue, uint64_t value);
uint64_t syncorda_atomic_u64_add(SyncordaAtomicUInt64 *atomicValue, uint64_t value);
int syncorda_unix_socket_address(const char *path, struct sockaddr_un *address, socklen_t *length);

#ifdef __cplusplus
}
#endif

#endif
