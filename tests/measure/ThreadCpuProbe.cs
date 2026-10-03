using System;
using System.Runtime.InteropServices;
using Godot;

// Test-only main-thread counters. CPU accounting may be coarse; cycles are not time.
public partial class ThreadCpuProbe : RefCounted
{
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentThread();
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentProcessorNumber();
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetThreadTimes(IntPtr thread, out long creation,
        out long exit, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryThreadCycleTime(IntPtr thread, out ulong cycles);

    // [wall_usec, native_thread_id, kernel_usec, user_usec, cycles, valid, processor]
    public long[] Sample()
    {
        if (!OperatingSystem.IsWindows()) return new long[] { 0, 0, 0, 0, 0, 0, 0 };
        IntPtr thread = GetCurrentThread();
        bool timed = GetThreadTimes(thread, out _, out _, out long kernel, out long user);
        bool cycled = QueryThreadCycleTime(thread, out ulong cycles);
        return new long[] { (long)Godot.Time.GetTicksUsec(), GetCurrentThreadId(),
            kernel / 10, user / 10, unchecked((long)cycles), timed && cycled ? 1 : 0,
            GetCurrentProcessorNumber() };
    }
}
