using System;
using Godot;

// Test-only cumulative counters. Never requests a collection or memory snapshot.
public partial class FleetDayGcProbe : RefCounted
{
    private readonly long[] counters = new long[5];

    // [gen0, gen1, gen2, cumulative_pause_usec, current_thread_allocated_bytes]
    // Reuse the CLR array; Godot marshaling still has its own diagnostic cost.
    public long[] Sample()
    {
        counters[0] = GC.CollectionCount(0);
        counters[1] = GC.CollectionCount(1);
        counters[2] = GC.CollectionCount(2);
        counters[3] = GC.GetTotalPauseDuration().Ticks / 10;
        counters[4] = GC.GetAllocatedBytesForCurrentThread();
        return counters;
    }
}
