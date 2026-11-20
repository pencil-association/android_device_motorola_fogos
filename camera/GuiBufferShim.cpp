// SPDX-License-Identifier: Apache-2.0

#include <cstddef>
#include <new>

#include <gui/BufferItem.h>
#include <gui/BufferItemConsumer.h>
#include <gui/Surface.h>
#include <utils/Timers.h>

namespace android {

// The ARM64 camera blob allocates these objects itself and reads these BufferItem fields.
static_assert(sizeof(BufferItem) == 0x118);
static_assert(offsetof(BufferItem, mGraphicBuffer) == 0x00);
static_assert(offsetof(BufferItem, mFence) == 0x08);
static_assert(offsetof(BufferItem, mCrop) == 0x20);
static_assert(sizeof(Surface) <= 0x1fe8);
static_assert(alignof(Surface) <= __STDCPP_DEFAULT_NEW_ALIGNMENT__);

status_t acquireLegacyBuffer(BufferItemConsumer*, BufferItem*, nsecs_t, bool)
        asm("_ZN7android18BufferItemConsumer13acquireBufferEPNS_10BufferItemElb");

status_t acquireLegacyBuffer(BufferItemConsumer* consumer, BufferItem* item, nsecs_t presentWhen,
                             bool waitForFence) {
    return consumer->acquireBuffer(item, presentWhen, waitForFence);
}

status_t releaseLegacyBuffer(BufferItemConsumer*, const BufferItem&, const sp<Fence>&)
        asm("_ZN7android18BufferItemConsumer13releaseBufferERKNS_10BufferItemERKNS_2spINS_5FenceEEE");

status_t releaseLegacyBuffer(BufferItemConsumer* consumer, const BufferItem& item,
                             const sp<Fence>& releaseFence) {
    return consumer->releaseBuffer(item, releaseFence);
}

void constructLegacySurface(Surface*, const sp<IGraphicBufferProducer>&, bool)
        asm("_ZN7android7SurfaceC1ERKNS_2spINS_22IGraphicBufferProducerEEEb");

void constructLegacySurface(Surface* surface, const sp<IGraphicBufferProducer>& producer,
                            bool controlledByApp) {
    new (surface) Surface(producer, controlledByApp);
}

}  // namespace android
