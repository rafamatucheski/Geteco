using System;
using System.Runtime.InteropServices;
using Godot;

// Contadores da thread principal só para teste. A contabilidade de CPU pode ser grosseira; ciclos não são tempo.
public partial class ThreadCpuProbe : RefCounted
{
    // Só âncoras esparsas, fora do observador de quadros. Os delimitadores QPC mostram a incerteza
    // de alinhamento de relógio; estes contadores não identificam estados do escalonador.
    public long[] ClockAnchor()
    {
        long before = System.Diagnostics.Stopwatch.GetTimestamp();
        long usec = (long)Godot.Time.GetTicksUsec();
        long utc = DateTime.UtcNow.ToFileTimeUtc();
        long after = System.Diagnostics.Stopwatch.GetTimestamp();
        return new long[] { before, usec, utc, after,
            System.Diagnostics.Stopwatch.Frequency,
            OperatingSystem.IsWindows() ? GetCurrentThreadId() : 0 };
    }
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
