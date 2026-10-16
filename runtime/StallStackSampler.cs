using Godot;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Amostrador de pilha nativa da thread principal durante travadas (diagnóstico, 16/10/2026).
// Só liga com HARBOR_STALL_STACKS=1 (o StallLog instancia). Motivo: o quadro isolado de 140–550 ms
// em render_bracket_ms (fase 3) não tinha span, compilação de pipeline, desenho, alocação nem
// liberação de memória de vídeo; nenhum contador do motor explicava. Aqui uma thread de fundo
// suspende a thread principal quando ela passa de 30 ms sem bater o ponto, copia RIP e o topo da
// pilha, retoma e só depois traduz endereços em módulo+deslocamento (sem alocar com a thread
// principal suspensa, para não travar em lock de heap ou do GC).
// Saída: linhas "STALL_STACK {json}" no stdout (o SessionDiagnostics também as guarda).
public partial class StallStackSampler : Node
{
    private const uint THREAD_SUSPEND_RESUME = 0x0002, THREAD_GET_CONTEXT = 0x0008, THREAD_QUERY_INFORMATION = 0x0040;
    private const uint CONTEXT_CONTROL = 0x00100001, CONTEXT_INTEGER = 0x00100002;
    private const int CONTEXT_SIZE = 1232, OFFSET_FLAGS = 0x30, OFFSET_RSP = 0x98, OFFSET_RIP = 0xF8;
    private const int STACK_BYTES = 65536;
    private const double TRIGGER_MS = 30.0;

    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr OpenThread(uint access, bool inherit, uint id);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint SuspendThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetThreadContext(IntPtr thread, IntPtr context);
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] private struct MemoryStatus { public uint Length, Load; public ulong TotalPhys, AvailPhys, TotalPage, AvailPage, TotalVirtual, AvailVirtual, AvailExtended; }
    [DllImport("kernel32.dll")] private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, IntPtr size, out IntPtr read);

    private IntPtr mainThread;
    private uint mainThreadId;
    private IntPtr contextRaw, context;
    private Thread worker;
    private volatile bool running;
    // Ponto batido pela thread principal (Stopwatch ticks) e fase atual.
    private long heartbeat;
    private volatile int phase; // 0 = process/física, 1 = desenho (entre frame_pre_draw e frame_post_draw)
    private readonly ConcurrentQueue<string> output = new();
    private readonly byte[] stack = new byte[STACK_BYTES];
    private (ulong Base, ulong End, string Name)[] modules = Array.Empty<(ulong, ulong, string)>();

    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        if (!OperatingSystem.IsWindows()) { QueueFree(); return; }
        mainThreadId = GetCurrentThreadId();
        mainThread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, false, mainThreadId);
        if (mainThread == IntPtr.Zero) { QueueFree(); return; }
        contextRaw = Marshal.AllocHGlobal(CONTEXT_SIZE + 16);
        context = new IntPtr((contextRaw.ToInt64() + 15) & ~15L);
        RefreshModules();
        RenderingServer.FramePreDraw += OnPreDraw;
        RenderingServer.FramePostDraw += OnPostDraw;
        Interlocked.Exchange(ref heartbeat, Stopwatch.GetTimestamp());
        running = true;
        worker = new Thread(Loop) { IsBackground = true, Name = "StallStackSampler", Priority = ThreadPriority.AboveNormal };
        worker.Start();
        GD.Print("StallStackSampler: amostrando a pilha da thread principal em travadas > ", TRIGGER_MS, " ms");
    }

    private void OnPreDraw() { phase = 1; Interlocked.Exchange(ref heartbeat, Stopwatch.GetTimestamp()); }
    private void OnPostDraw() { phase = 0; Interlocked.Exchange(ref heartbeat, Stopwatch.GetTimestamp()); }

    public override void _Process(double delta)
    {
        Interlocked.Exchange(ref heartbeat, Stopwatch.GetTimestamp());
        while (output.TryDequeue(out var line)) GD.Print("STALL_STACK ", line);
    }

    public override void _PhysicsProcess(double delta) => Interlocked.Exchange(ref heartbeat, Stopwatch.GetTimestamp());

    public override void _ExitTree()
    {
        running = false;
        worker?.Join(200);
        RenderingServer.FramePreDraw -= OnPreDraw;
        RenderingServer.FramePostDraw -= OnPostDraw;
    }

    private void RefreshModules()
    {
        var list = new List<(ulong, ulong, string)>();
        foreach (ProcessModule module in Process.GetCurrentProcess().Modules)
        {
            ulong start = (ulong)module.BaseAddress.ToInt64();
            list.Add((start, start + (ulong)module.ModuleMemorySize, module.ModuleName));
        }
        list.Sort((a, b) => a.Item1.CompareTo(b.Item1));
        modules = list.ToArray();
    }

    private int ModuleOf(ulong address)
    {
        var table = modules;
        int lo = 0, hi = table.Length - 1;
        while (lo <= hi)
        {
            int mid = (lo + hi) / 2;
            if (address < table[mid].Base) hi = mid - 1;
            else if (address >= table[mid].End) lo = mid + 1;
            else return mid;
        }
        return -1;
    }

    // Endereço de retorno plausível: o byte antes dele fecha uma instrução call (E8 rel32 ou FF /2).
    // Lido com ReadProcessMemory: ler direto uma página sem acesso derruba o processo (AV não é capturável).
    private readonly byte[] code = new byte[8];
    private bool AfterCall(ulong address)
    {
        if (address < 8) return false;
        if (!ReadProcessMemory(GetCurrentProcess(), new IntPtr((long)address - 8), code, new IntPtr(8), out _)) return false;
        if (code[3] == 0xE8) return true;
        for (int back = 2; back <= 7; back++)
        {
            if (code[8 - back] != 0xFF) continue;
            if (((code[8 - back + 1] >> 3) & 7) == 2) return true;
        }
        return false;
    }

    private void Loop()
    {
        var frames = new List<(double Ms, string Stack)>(256);
        long stallStart = 0;
        int stallPhase = 0;
        double ticksPerMs = Stopwatch.Frequency / 1000.0;
        while (running)
        {
            Thread.Sleep(2);
            long beat = Interlocked.Read(ref heartbeat);
            long now = Stopwatch.GetTimestamp();
            double stuckMs = (now - beat) / ticksPerMs;
            if (stuckMs < TRIGGER_MS)
            {
                if (frames.Count > 0) { Emit(frames, (beat - stallStart) / ticksPerMs, stallPhase); frames.Clear(); }
                continue;
            }
            if (frames.Count == 0) { stallStart = beat; stallPhase = phase; othersTaken = false; others = null; }
            if (frames.Count >= 256) continue;
            ulong rip, rsp;
            IntPtr read = IntPtr.Zero;
            bool copied;
            // Nada de alocação gerenciada entre Suspend e Resume.
            if (SuspendThread(mainThread) == uint.MaxValue) continue;
            try
            {
                Marshal.WriteInt32(context, OFFSET_FLAGS, unchecked((int)(CONTEXT_CONTROL | CONTEXT_INTEGER)));
                if (!GetThreadContext(mainThread, context)) continue;
                rip = (ulong)Marshal.ReadInt64(context, OFFSET_RIP);
                rsp = (ulong)Marshal.ReadInt64(context, OFFSET_RSP);
                copied = ReadProcessMemory(GetCurrentProcess(), new IntPtr((long)rsp), stack, new IntPtr(STACK_BYTES), out read)
                    || ReadProcessMemory(GetCurrentProcess(), new IntPtr((long)rsp), stack, new IntPtr(2048), out read);
            }
            finally { ResumeThread(mainThread); }
            frames.Add(((now - beat) / ticksPerMs, Describe(rip, copied ? (int)read.ToInt64() : 0)));
            // Uma vez por travada longa (~80 ms dentro dela): retrato das outras threads, para ver quem
            // segura o lock que a thread principal espera (compilador do driver, gravação de cache...).
            if (!othersTaken && (now - beat) / ticksPerMs > 80.0) { othersTaken = true; others = SnapshotOthers(); }
        }
    }

    private string Describe(ulong rip, int bytes)
    {
        var text = new StringBuilder(256);
        Append(text, rip);
        int found = 0;
        for (int offset = 0; offset + 8 <= bytes && found < 48; offset += 8)
        {
            ulong value = BitConverter.ToUInt64(stack, offset);
            int index = ModuleOf(value);
            if (index < 0 || !AfterCall(value)) continue;
            text.Append(" < ");
            Append(text, value);
            found++;
        }
        return text.ToString();
    }

    private void Append(StringBuilder text, ulong address)
    {
        int index = ModuleOf(address);
        if (index < 0) { RefreshModules(); index = ModuleOf(address); }
        if (index < 0) { text.Append("0x").Append(address.ToString("x")); return; }
        var module = modules[index];
        text.Append(module.Name).Append("+0x").Append((address - module.Base).ToString("x"));
    }

    // RAM livre da máquina na hora: a hipótese é corte de memória (trim) do driver sob pressão de memória.
    private static ulong AvailPhysMb()
    {
        var status = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        return GlobalMemoryStatusEx(ref status) ? status.AvailPhys / 1048576 : 0;
    }

    private bool othersTaken;
    private List<string> others;

    private List<string> SnapshotOthers()
    {
        var result = new List<string>();
        uint self = GetCurrentThreadId();
        uint mainId = mainThreadId;
        ProcessThreadCollection threads;
        try { threads = Process.GetCurrentProcess().Threads; } catch (Exception) { return result; }
        foreach (ProcessThread thread in threads)
        {
            uint id = (uint)thread.Id;
            if (id == self || id == mainId) continue;
            IntPtr handle = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, false, id);
            if (handle == IntPtr.Zero) continue;
            ulong rip = 0;
            IntPtr read = IntPtr.Zero;
            bool copied = false;
            if (SuspendThread(handle) != uint.MaxValue)
            {
                try
                {
                    Marshal.WriteInt32(context, OFFSET_FLAGS, unchecked((int)(CONTEXT_CONTROL | CONTEXT_INTEGER)));
                    if (GetThreadContext(handle, context))
                    {
                        rip = (ulong)Marshal.ReadInt64(context, OFFSET_RIP);
                        ulong rsp = (ulong)Marshal.ReadInt64(context, OFFSET_RSP);
                        copied = ReadProcessMemory(GetCurrentProcess(), new IntPtr((long)rsp), stack, new IntPtr(STACK_BYTES), out read)
                            || ReadProcessMemory(GetCurrentProcess(), new IntPtr((long)rsp), stack, new IntPtr(2048), out read);
                    }
                }
                finally { ResumeThread(handle); }
            }
            CloseHandle(handle);
            if (rip == 0) continue;
            string text = Describe(rip, copied ? (int)read.ToInt64() : 0);
            // Threads ociosas esperando trabalho não interessam: só as que estão fora de espera pura
            // ou dentro do driver de vídeo.
            if (text.Contains("nvoglv64") || text.Contains("nvgpucomp") || text.Contains("vulkan-1") || !text.StartsWith("ntdll.dll"))
                result.Add(id + ": " + text);
        }
        return result;
    }

    private void Emit(List<(double Ms, string Stack)> frames, double stallMs, int stallPhase)
    {
        var counts = new Dictionary<string, int>();
        var tops = new Dictionary<string, int>();
        var chains = new Dictionary<string, int>();
        foreach (var (_, stackText) in frames)
        {
            counts[stackText] = counts.GetValueOrDefault(stackText) + 1;
            // Cadeia só de módulos (sem deslocamento): agrupa amostras do mesmo caminho.
            var chain = new StringBuilder();
            string last = "";
            foreach (string part in stackText.Split(" < "))
            {
                int cut = part.IndexOf("+0x", StringComparison.Ordinal);
                string name = cut > 0 ? part[..cut] : part;
                if (name == last) continue;
                if (chain.Length > 0) chain.Append('<');
                chain.Append(name);
                last = name;
            }
            chains[chain.ToString()] = chains.GetValueOrDefault(chain.ToString()) + 1;
            string top = stackText.Split(" < ")[0];
            int plus = top.IndexOf("+0x", StringComparison.Ordinal);
            string module = plus > 0 ? top[..plus] : top;
            tops[module] = tops.GetValueOrDefault(module) + 1;
        }
        var stacks = new List<KeyValuePair<string, int>>(counts);
        stacks.Sort((a, b) => b.Value.CompareTo(a.Value));
        var json = new StringBuilder();
        json.Append("{\"t_ms\":").Append(Time.GetTicksMsec()).Append(",\"stall_ms\":").Append(stallMs.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture))
            .Append(",\"avail_phys_mb\":").Append(AvailPhysMb())
            .Append(",\"phase\":\"").Append(stallPhase == 1 ? "render" : "process").Append("\",\"samples\":").Append(frames.Count)
            .Append(",\"top_modules\":{");
        bool first = true;
        foreach (var pair in tops) { if (!first) json.Append(','); first = false; json.Append('"').Append(pair.Key).Append("\":").Append(pair.Value); }
        json.Append("},\"chains\":{");
        first = true;
        foreach (var pair in chains) { if (!first) json.Append(','); first = false; json.Append('"').Append(pair.Key).Append("\":").Append(pair.Value); }
        json.Append("},\"stacks\":[");
        for (int i = 0; i < Math.Min(6, stacks.Count); i++)
        {
            if (i > 0) json.Append(',');
            json.Append("{\"n\":").Append(stacks[i].Value).Append(",\"s\":\"").Append(stacks[i].Key).Append("\"}");
        }
        json.Append(']');
        if (others != null)
        {
            json.Append(",\"others\":[");
            for (int i = 0; i < others.Count; i++) { if (i > 0) json.Append(','); json.Append('"').Append(others[i]).Append('"'); }
            json.Append(']');
        }
        json.Append('}');
        output.Enqueue(json.ToString());
    }
}
