using Godot;
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;

// First autoload: one process = one session. Never changes gameplay or saves.
public partial class SessionDiagnostics : Node
{
    private SessionLogSink sink;
    private readonly System.Collections.Generic.List<double> frames = new(512);
    private long previous, window;
    private Process process;
    private double previousCpu;
    // Amostra de CPU/memória do processo feita fora da thread principal (16/10/2026). No Windows,
    // Process.Refresh + WorkingSet64/PrivateMemorySize64 tiram um retrato de TODOS os processos
    // da máquina (NtQuerySystemInformation): 18–25 ms por segundo na thread do jogo, medidos no
    // export pelo telemetry_main_thread_usec. Era o pico de ~1 Hz sem span das rotas da cidade.
    private sealed record ProcessSample(double CpuPercent, long WorkingSet, long PrivateMemory, long SampledAt);
    private volatile ProcessSample processSample;
    private System.Threading.Timer processTimer;
    private int processSampling;
    private long previousCpuAt;
    private JsonElement worldContext;
    private long telemetryUsec;
    private readonly System.Collections.Generic.List<int> frameContextIds = new(512);
    private int contextId;
    private (string Scene, bool Paused, bool Focused, int MaxFps, Vector2I Size, DisplayServer.VSyncMode Vsync) frameState;
    private int runtimeStateId;
    private readonly System.Collections.Generic.List<int> frameStateIds = new(512);
    public long TelemetryUsec => Interlocked.Read(ref telemetryUsec);
    // The main thread publishes immutable context; error/watchdog callbacks never touch Godot.
    public int UpdateContext(string json)
    {
        try {
            using var doc = JsonDocument.Parse(json);
            worldContext = doc.RootElement.Clone();
            sink?.SetContext(worldContext);
            contextId++;
            sink?.Record(new { type = "context_update", id = contextId, context = worldContext });
            return contextId;
        } catch (JsonException e) { sink?.Record(new { type = "telemetry_error", error = e.Message }); return contextId; }
    }
    public string LogPath => sink?.Folder ?? "";
    public string WriterFailure => sink?.Failure ?? "";
    public long DroppedRecords => sink?.Dropped ?? 0;
    private static object EngineMonitors() => new {
        scope = "latest_available_not_exact_frame; unsupported_monitors_can_be_zero",
        native_memory_bytes = Performance.GetMonitor(Performance.Monitor.MemoryStatic),
        native_memory_peak_bytes = Performance.GetMonitor(Performance.Monitor.MemoryStaticMax),
        deferred_message_buffer_peak_bytes = Performance.GetMonitor(Performance.Monitor.MemoryMessageBufferMax),
        resources = Performance.GetMonitor(Performance.Monitor.ObjectResourceCount),
        orphan_nodes = Performance.GetMonitor(Performance.Monitor.ObjectOrphanNodeCount),
        rendered_objects = Performance.GetMonitor(Performance.Monitor.RenderTotalObjectsInFrame),
        rendered_primitives = Performance.GetMonitor(Performance.Monitor.RenderTotalPrimitivesInFrame),
        texture_memory_bytes = Performance.GetMonitor(Performance.Monitor.RenderTextureMemUsed),
        buffer_memory_bytes = Performance.GetMonitor(Performance.Monitor.RenderBufferMemUsed),
        physics_3d_active_objects = Performance.GetMonitor(Performance.Monitor.Physics3DActiveObjects),
        physics_3d_collision_pairs = Performance.GetMonitor(Performance.Monitor.Physics3DCollisionPairs),
        physics_3d_islands = Performance.GetMonitor(Performance.Monitor.Physics3DIslandCount),
        physics_2d_active_objects = Performance.GetMonitor(Performance.Monitor.Physics2DActiveObjects),
        physics_2d_collision_pairs = Performance.GetMonitor(Performance.Monitor.Physics2DCollisionPairs),
        navigation_ms = Performance.GetMonitor(Performance.Monitor.TimeNavigationProcess) * 1000,
        audio_output_latency_ms = Performance.GetMonitor(Performance.Monitor.AudioOutputLatency) * 1000
    };
    // Todos os valores são lidos na hora (thread principal); o objeto resultante é só dado CLR imutável,
    // seguro para serializar na thread de escrita.
    private object RuntimeSnapshotObject() => new {
        engine_usec = Time.GetTicksUsec(), process_frame = Engine.GetProcessFrames(),
        gc_collections = new[] { GC.CollectionCount(0), GC.CollectionCount(1), GC.CollectionCount(2) },
        allocated_bytes = GC.GetTotalAllocatedBytes(false), managed_bytes = GC.GetTotalMemory(false),
        gc_pause_ms = GC.GetTotalPauseDuration().TotalMilliseconds,
        writer_queue = sink?.QueueCount ?? 0, records_dropped = DroppedRecords,
        telemetry_main_thread_usec = TelemetryUsec, writer = sink?.WriterSnapshot(),
        engine_monitors = EngineMonitors(),
        active_operations = sink?.ActiveOperations() ?? Array.Empty<object>() };
    public string RuntimeSnapshot() => JsonSerializer.Serialize(RuntimeSnapshotObject());

    // Retrato guardado no quadro do pico (auditoria 19/10, §1): o SessionSystemProfile pede o retrato no
    // callback do pico e manda o JSON do registro só nos callbacks seguintes, fatiado. Serializar o
    // retrato e reparsear em GDScript (o caminho antigo) custava parte dos 11–21 ms do segundo pico.
    // Poucos e com teto: um id não consumido some quando chegam HeldSnapshotLimit mais novos.
    private const int HeldSnapshotLimit = 64;
    private readonly System.Collections.Generic.Dictionary<int, (object Runtime, JsonElement Context)> heldSnapshots = new();
    private readonly System.Collections.Generic.Queue<int> heldOrder = new();
    private int heldSnapshotId;
    public int HoldRuntimeSnapshot()
    {
        if (sink == null) return 0;
        long began = Stopwatch.GetTimestamp();
        int id = ++heldSnapshotId;
        heldSnapshots[id] = (RuntimeSnapshotObject(), worldContext);
        heldOrder.Enqueue(id);
        while (heldOrder.Count > HeldSnapshotLimit) heldSnapshots.Remove(heldOrder.Dequeue());
        Interlocked.Add(ref telemetryUsec, (Stopwatch.GetTimestamp() - began) * 1000000 / Stopwatch.Frequency);
        return id;
    }
    // O JSON chega pronto do GDScript; "runtime" (e "context", se pedido e ausente) entram na thread de
    // escrita a partir do retrato guardado. Id 0 ou vencido: retrato de agora, marcado como tal.
    public void RecordProfileWithSnapshot(string json, int snapshotId, bool attachContext)
    {
        if (sink == null) return;
        (object Runtime, JsonElement Context) snapshot = default;
        bool held = snapshotId != 0 && heldSnapshots.Remove(snapshotId, out snapshot);
        if (!held) snapshot = (RuntimeSnapshotObject(), worldContext);
        sink.ProfileWith(json, snapshot.Runtime, attachContext ? snapshot.Context : default, held ? "held_at_request" : "taken_at_send");
    }

    public override void _EnterTree()
    {
        ProcessMode = ProcessModeEnum.Always;
        if (System.Environment.GetEnvironmentVariable("HARBOR_SESSION_LOG") == "0") return;
        try
        {
            string folder = ProjectSettings.GlobalizePath("user://session-logs");
            sink = new SessionLogSink(folder);
            OS.AddLogger(sink);
            process = Process.GetCurrentProcess();
            previousCpu = process.TotalProcessorTime.TotalMilliseconds;
            previous = window = previousCpuAt = Stopwatch.GetTimestamp();
            processTimer = new System.Threading.Timer(SampleProcess, null, 1000, 1000);
            sink.Record(new { type = "session_start", utc = DateTime.UtcNow, pid = System.Environment.ProcessId,
                engine = Engine.GetVersionInfo()["string"].AsString(), version = ProjectSettings.GetSetting("application/config/version").AsString(),
                cpu = OS.GetProcessorName(), logical_processors = System.Environment.ProcessorCount,
                gpu = RenderingServer.GetVideoAdapterName(), renderer = RenderingServer.GetCurrentRenderingMethod(),
                dotnet = System.Environment.Version.ToString(), max_fps = Engine.MaxFps,
                resolution = GetTree().Root.Size.ToString(), vsync = DisplayServer.WindowGetVsyncMode().ToString(),
                debugger = EngineDebugger.IsActive(), schema = 5,
                debug_build = OS.IsDebugBuild(),
                // Separa editor, export de debug e export release: os números só se comparam entre o mesmo tipo.
                build_kind = OS.HasFeature("editor") ? "editor" : OS.HasFeature("release") ? "export_release" : "export_debug",
                executable = OS.GetExecutablePath(),
                launch_args = OS.GetCmdlineArgs(),
                window_mode = DisplayServer.WindowGetMode().ToString(),                clock_sync = new { engine_usec = Time.GetTicksUsec(), stopwatch_ticks = Stopwatch.GetTimestamp(), stopwatch_frequency = Stopwatch.Frequency },
                frame_history_seconds = 2, frame_history_capacity = 360,
                slow_operation_ms = 2, pending_operation_ms = 5000, max_active_operations = 128,
                coverage = "explicit_instrumentation_not_all_scripts",
                limitations = new[] { "GPU samples are asynchronous; no exact spike attribution", "No native stacks or pre-autoload work", "No automatic logic-bug detection" },
                telemetry_limits = new { queue_records = 8192, profile_record_chars = 2 * 1024 * 1024, profile_queue_payload_bytes = 32 * 1024 * 1024, part_bytes = 32 * 1024 * 1024 },
                system_profile = System.Environment.GetEnvironmentVariable("HARBOR_SESSION_PROFILE") != "0" });
            AppDomain.CurrentDomain.UnhandledException += OnUnhandledException;
            System.Threading.Tasks.TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
            GD.Print("SessionDiagnostics: ", sink.Folder);
        }
        catch (Exception e)
        {
            // Report once; lack of writable storage must not stop the game.
            GD.PrintErr("SessionDiagnostics indisponível: " + e.Message);
            SetProcess(false);
        }
    }

    public override void _Ready()
    {
        if (sink == null || System.Environment.GetEnvironmentVariable("HARBOR_SESSION_PROFILE") == "0") return;
        try
        {
            var script = GD.Load<GDScript>("res://runtime/SessionSystemProfile.gd");
            var profiler = script.New().AsGodotObject() as Node;
            profiler.Name = "SystemProfile";
            AddChild(profiler);
        }
        catch (Exception e) { sink.Record(new { type = "telemetry_error", error = e.ToString() }); }
    }

    // JSON is parsed on the writer thread, never serializing Godot objects there.
    public void RecordProfile(string json) => sink?.Profile(json);

    public long BeginOperation(string system, string operation, string source, string detailsJson)
        => sink?.BeginOperation(system, operation, source, detailsJson) ?? 0;
    public void EndOperation(long token, string status) => sink?.EndOperation(token, status);
    public long BeginOperationAt(string system, string operation, string source, string detailsJson,
        long engineUsec, long frame, long parentToken) => sink?.BeginOperation(system, operation, source, detailsJson, engineUsec, frame, parentToken) ?? 0;
    private void OnUnhandledException(object sender, UnhandledExceptionEventArgs e)
        => sink?.ManagedException("managed_unhandled_exception", e.ExceptionObject.ToString(), e.IsTerminating);
    private void OnUnobservedTaskException(object sender, System.Threading.Tasks.UnobservedTaskExceptionEventArgs e)
        => sink?.ManagedException("managed_unobserved_task_exception", e.Exception.ToString(), false);

    public override void _Process(double delta)
    {
        if (sink == null) return;
        long now = Stopwatch.GetTimestamp();
        var state = (GetTree().CurrentScene?.SceneFilePath ?? "", GetTree().Paused, DisplayServer.WindowIsFocused(), Engine.MaxFps, GetTree().Root.Size, DisplayServer.WindowGetVsyncMode());
        if (state != frameState) {
            frameState = state;
            runtimeStateId++;
            sink.Record(new { type = "runtime_state_changed", id = runtimeStateId, engine_usec = Time.GetTicksUsec(), process_frame = Engine.GetProcessFrames(),
                scene = GetTree().CurrentScene?.SceneFilePath ?? "", paused = GetTree().Paused,
                focused = DisplayServer.WindowIsFocused(), max_fps = Engine.MaxFps,
                resolution = GetTree().Root.Size.ToString(), vsync = DisplayServer.WindowGetVsyncMode().ToString(),
                interval_semantics = "state_at_interval_end" });
        }
        frameContextIds.Add(contextId);
        frameStateIds.Add(runtimeStateId);
        frames.Add((now - previous) * 1000.0 / Stopwatch.Frequency);
        previous = now;
        sink.Touch(now);
        if ((now - window) < Stopwatch.Frequency) {
            Interlocked.Add(ref telemetryUsec, (Stopwatch.GetTimestamp() - now) * 1000000 / Stopwatch.Frequency);
            return;
        }
        try
        {
            var sample = processSample;
            sink.Metrics(frames.ToArray(), frameContextIds.ToArray(), frameStateIds.ToArray(), new {
                cpu_percent = sample?.CpuPercent ?? -1.0,
                working_set_bytes = sample?.WorkingSet ?? -1, managed_bytes = GC.GetTotalMemory(false),
                private_memory_bytes = sample?.PrivateMemory ?? -1, engine_monitors = EngineMonitors(),
                process_sample_scope = "background_sample_up_to_1s_old",
                engine_usec = Time.GetTicksUsec(), process_frame = Engine.GetProcessFrames(),
                gc_collections = new[] { GC.CollectionCount(0), GC.CollectionCount(1), GC.CollectionCount(2) },
                allocated_bytes = GC.GetTotalAllocatedBytes(false), gc_pause_ms = GC.GetTotalPauseDuration().TotalMilliseconds,
                writer_queue = sink.QueueCount, records_dropped = sink.Dropped,
                world = worldContext.ValueKind == JsonValueKind.Undefined ? (object)null : worldContext,
                telemetry_main_thread_usec = TelemetryUsec, writer = sink.WriterSnapshot(),
                monitor_scope = "latest_available_not_exact_frame",
                process_ms = Performance.GetMonitor(Performance.Monitor.TimeProcess) * 1000,
                physics_ms = Performance.GetMonitor(Performance.Monitor.TimePhysicsProcess) * 1000,
                nodes = Performance.GetMonitor(Performance.Monitor.ObjectNodeCount),
                objects = Performance.GetMonitor(Performance.Monitor.ObjectCount),
                draw_calls = Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame),
                video_memory_bytes = Performance.GetMonitor(Performance.Monitor.RenderVideoMemUsed),
                scene = GetTree().CurrentScene?.SceneFilePath ?? "", paused = GetTree().Paused,
                focused = DisplayServer.WindowIsFocused(), max_fps = Engine.MaxFps,
                resolution = GetTree().Root.Size.ToString(), vsync = DisplayServer.WindowGetVsyncMode().ToString()
            });
        }
        catch (Exception e) { sink.Record(new { type = "telemetry_error", error = e.ToString() }); }
        frames.Clear();
        frameContextIds.Clear();
        frameStateIds.Clear();
        window = now;
        Interlocked.Add(ref telemetryUsec, (Stopwatch.GetTimestamp() - now) * 1000000 / Stopwatch.Frequency);
    }

    // Thread do Timer: só System.Diagnostics, nenhuma API do Godot.
    private void SampleProcess(object state)
    {
        if (Interlocked.Exchange(ref processSampling, 1) == 1) return;
        try
        {
            var current = process;
            if (current == null) return;
            current.Refresh();
            long now = Stopwatch.GetTimestamp();
            double cpu = current.TotalProcessorTime.TotalMilliseconds;
            double elapsed = Math.Max(1e-3, (now - previousCpuAt) * 1000.0 / Stopwatch.Frequency);
            // Process CPU normalized to the whole machine, not Godot's TIME_PROCESS monitor.
            processSample = new ProcessSample((cpu - previousCpu) / elapsed / System.Environment.ProcessorCount * 100,
                current.WorkingSet64, current.PrivateMemorySize64, now);
            previousCpu = cpu;
            previousCpuAt = now;
        }
        catch (Exception) { }
        finally { Volatile.Write(ref processSampling, 0); }
    }

    public override void _ExitTree()
    {
        processTimer?.Dispose();
        processTimer = null;
        if (sink == null) return;
        AppDomain.CurrentDomain.UnhandledException -= OnUnhandledException;
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException -= OnUnobservedTaskException;
        OS.RemoveLogger(sink);
        sink.Record(new { type = "session_end", utc = DateTime.UtcNow, remaining_frame_ms = frames.ToArray(), remaining_context_ids = frameContextIds.ToArray(), remaining_state_ids = frameStateIds.ToArray(),
            writer = sink.WriterSnapshot(), telemetry_main_thread_usec = TelemetryUsec,
            unfinished_operations = sink.ActiveOperations() });
        sink.Close();
        process?.Dispose();
    }
}

// Only immutable CLR data crosses to the writer. No Godot API calls on its thread.
public partial class SessionLogSink : Logger
{
    private readonly BlockingCollection<object> queue = new(8192);
    private readonly Thread writer;
    private readonly long start = Stopwatch.GetTimestamp();
    private long lastFrame, dropped, sequence, written, bytesWritten, writerUsec, maximumQueue, profileQueuedBytes;
    private long droppedBudget, droppedCapacity, droppedOversize, droppedUnavailable;
    private const long ProfileBudgetBytes = 32 * 1024 * 1024;
    private string publishedContext = "{}";
    public void SetContext(JsonElement context) => Volatile.Write(ref publishedContext, context.GetRawText());
    private JsonElement ContextSnapshot() { using var doc = JsonDocument.Parse(Volatile.Read(ref publishedContext)); return doc.RootElement.Clone(); }
    public object WriterSnapshot() => new { records_written = Interlocked.Read(ref written), bytes_written = Interlocked.Read(ref bytesWritten),
        writer_cpu_wall_usec = Interlocked.Read(ref writerUsec), queue_high_water = Interlocked.Read(ref maximumQueue), queue_capacity = 8192, profile_queued_bytes = Interlocked.Read(ref profileQueuedBytes), profile_budget_bytes = ProfileBudgetBytes,
        dropped_by_reason = new { payload_budget = Interlocked.Read(ref droppedBudget), queue_capacity = Interlocked.Read(ref droppedCapacity), oversize = Interlocked.Read(ref droppedOversize), writer_unavailable_or_closed = Interlocked.Read(ref droppedUnavailable) } };
    private volatile string failure = "";
    public string Folder { get; }
    public string Failure => failure;
    public long Dropped => Interlocked.Read(ref dropped);
    public int QueueCount => queue.Count;
    private record Envelope(long sequence, double elapsed_ms, DateTime utc, object data);
    private record FrameWindow(double[] Values, int[] ContextIds, int[] StateIds, object Context);
    private record ProfileRecord(string Json);
    private record RichProfileRecord(string Json, object Runtime, JsonElement Context, string SnapshotScope);
    private record Operation(long id, string system, string operation, string source, JsonElement details, long started, long engine_usec, long process_frame, long parent_id);
    private readonly ConcurrentDictionary<long, Operation> active = new();
    private long operationId;

    public long BeginOperation(string system, string operation, string source, string detailsJson, long engineUsec = 0, long frame = 0, long parentToken = 0)
    {
        if (active.Count >= 128)
        {
            Record(new { type = "operation_tracking_overflow", system, operation });
            return 0;
        }
        try
        {
            using var details = JsonDocument.Parse(detailsJson);
            var entry = new Operation(Interlocked.Increment(ref operationId), system, operation, source,
                details.RootElement.Clone(), Stopwatch.GetTimestamp(), engineUsec, frame, parentToken);
            active[entry.id] = entry;
            Record(new { type = "operation_begin", entry.id, system, operation, source, entry.details, entry.engine_usec, entry.process_frame, entry.parent_id, managed_thread_id = System.Environment.CurrentManagedThreadId });
            return entry.id;
        }
        catch (JsonException e) { Record(new { type = "telemetry_error", error = e.Message }); return 0; }
    }

    public void EndOperation(long token, string status)
    {
        if (!active.TryRemove(token, out var entry)) return;
        Record(new { type = "operation_end", entry.id, entry.system, entry.operation, entry.source, entry.details,
            entry.engine_usec, entry.process_frame, entry.parent_id, status, duration_ms = (Stopwatch.GetTimestamp() - entry.started) * 1000.0 / Stopwatch.Frequency,
            timing = "wall_inclusive" });
    }

    public object[] ActiveOperations(double minimumMs = 0)
    {
        long now = Stopwatch.GetTimestamp();
        return active.Values.Where(e => (now - e.started) * 1000.0 / Stopwatch.Frequency >= minimumMs)
            .OrderBy(e => e.id).Select(e => (object)new { e.id, e.system, e.operation, e.source, e.details,
                e.engine_usec, e.process_frame, e.parent_id, elapsed_ms = (now - e.started) * 1000.0 / Stopwatch.Frequency }).ToArray();
    }

    public SessionLogSink(string root)
    {
        Folder = Path.Combine(root, DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff") + "-" + System.Environment.ProcessId + "-" + Guid.NewGuid().ToString("N")[..8]);
        Directory.CreateDirectory(Folder);
        // Opening before registration allows storage failures to be reported outside Logger callbacks.
        var stream = OpenPart(0);
        lastFrame = start;
        writer = new Thread(() => WriteLoop(stream)) { IsBackground = true, Name = "Harbor session log" };
        writer.Start();
    }

    private StreamWriter OpenPart(int part) => new(new FileStream(Path.Combine(Folder, $"session-{part:D3}.jsonl"),
        FileMode.CreateNew, System.IO.FileAccess.Write, FileShare.Read, 65536, FileOptions.SequentialScan));
    public void Touch(long timestamp) => Interlocked.Exchange(ref lastFrame, timestamp);
    public void Metrics(double[] values, int[] contextIds, int[] stateIds, object context) => Record(new FrameWindow(values, contextIds, stateIds, context));
    public void Profile(string json) {
        if (json.Length > 2 * 1024 * 1024) { Record(new { type = "profile_record_oversize", chars = json.Length }); Interlocked.Increment(ref droppedOversize); Interlocked.Increment(ref dropped); return; }
        Record(new ProfileRecord(json));
    }
    // Mesmo teto e orçamento do Profile; runtime/context já são dados CLR lidos na thread principal.
    public void ProfileWith(string json, object runtime, JsonElement context, string snapshotScope) {
        if (json.Length > 2 * 1024 * 1024) { Record(new { type = "profile_record_oversize", chars = json.Length }); Interlocked.Increment(ref droppedOversize); Interlocked.Increment(ref dropped); return; }
        Record(new RichProfileRecord(json, runtime, context, snapshotScope));
    }
    public void Record(object data)
    {
        long profileCost = data is ProfileRecord payload ? payload.Json.Length * 2L : data is RichProfileRecord rich ? rich.Json.Length * 2L : 0;
        if (profileCost > 0 && Interlocked.Add(ref profileQueuedBytes, profileCost) > ProfileBudgetBytes) {
            Interlocked.Add(ref profileQueuedBytes, -profileCost);
            Interlocked.Increment(ref droppedBudget);
            Interlocked.Increment(ref dropped);
            return;
        }
        bool accepted = false;
        if (failure.Length != 0) { Interlocked.Add(ref profileQueuedBytes, -profileCost); Interlocked.Increment(ref droppedUnavailable); Interlocked.Increment(ref dropped); return; }
        try
        {
            accepted = queue.TryAdd(new Envelope(Interlocked.Increment(ref sequence), (Stopwatch.GetTimestamp() - start) * 1000.0 / Stopwatch.Frequency, DateTime.UtcNow, data));
            if (!accepted) { Interlocked.Increment(ref droppedCapacity); Interlocked.Increment(ref dropped); }
        }
        catch (InvalidOperationException) { Interlocked.Increment(ref droppedUnavailable); Interlocked.Increment(ref dropped); }
        if (!accepted && profileCost > 0) Interlocked.Add(ref profileQueuedBytes, -profileCost);
        long size = queue.Count;
        if (size > Interlocked.Read(ref maximumQueue)) Interlocked.Exchange(ref maximumQueue, size);
    }

    public void ManagedException(string type, string error, bool terminating) => Record(new {
        type, error, terminating, context = ContextSnapshot(), active_operations = ActiveOperations(),
        managed_thread_id = System.Environment.CurrentManagedThreadId,
        attribution = "concurrent_context_not_proven_cause" });

    public override void _LogMessage(string message, bool error) => Record(new { type = error ? "stderr" : "stdout", message });

    // Erro repetido (teste de 16/10): o mesmo erro do CobraPatrol a cada passo de física gravou 9.155
    // registros com retrato completo do jogo (~20 KB cada, 75% do log) e os picos foram de 19 para 175 por
    // minuto enquanto durou. O retrato completo vai só nas primeiras ocorrências de cada ponto; depois, uma
    // contagem por segundo.
    private const int ERROR_FULL_RECORDS = 3;
    private sealed class ErrorRepeat { public long Count; public long Suppressed; public long ReportedAt; }
    private readonly ConcurrentDictionary<string, ErrorRepeat> errorRepeats = new();

    public override void _LogError(string function, string file, int line, string code, string rationale,
        bool editorNotify, int errorType, Godot.Collections.Array<ScriptBacktrace> scriptBacktraces)
    {
        var repeat = errorRepeats.GetOrAdd(file + ":" + line + "::" + code, _ => new ErrorRepeat());
        long count = Interlocked.Increment(ref repeat.Count);
        if (count > ERROR_FULL_RECORDS)
        {
            Interlocked.Increment(ref repeat.Suppressed);
            long now = Stopwatch.GetTimestamp();
            long last = Interlocked.Read(ref repeat.ReportedAt);
            if (now - last >= Stopwatch.Frequency && Interlocked.CompareExchange(ref repeat.ReportedAt, now, last) == last)
            {
                long suppressed = Interlocked.Exchange(ref repeat.Suppressed, 0);
                Record(new { type = "error_repeat", error_type = errorType, function, file, line, code,
                    source_key = file + "::" + function, total = count, suppressed_since_last = suppressed,
                    attribution = "repeated_error_context_omitted" });
            }
            return;
        }
        try
        {
            var traces = new string[scriptBacktraces.Count];
            for (int i = 0; i < traces.Length; i++) traces[i] = scriptBacktraces[i].Format();
            Record(new { type = "error", error_type = errorType, function, file, line, code, rationale, backtraces = traces,
                source_key = file + "::" + function, context = ContextSnapshot(), managed_thread_id = System.Environment.CurrentManagedThreadId, active_operations = ActiveOperations(),
                attribution = "source_and_concurrent_operations_not_proven_cause" });
        }
        catch (Exception e) { Record(new { type = "logger_capture_error", error = e.Message, file, line, code, rationale }); }
    }

    private void WriteLoop(StreamWriter output)
    {
        int part = 0;
        long flushed = Stopwatch.GetTimestamp();
        long reportedDrops = 0;
        long summaryAt = Stopwatch.GetTimestamp();
        var summary = new SessionLogSummary();
        void WriteAuxiliary(object data) {
            long began = Stopwatch.GetTimestamp();
            var envelope = new Envelope(Interlocked.Increment(ref sequence), (began - start) * 1000.0 / Stopwatch.Frequency, DateTime.UtcNow, data);
            string line = JsonSerializer.Serialize(envelope);
            output.WriteLine(line);
            using (var parsed = JsonDocument.Parse(line)) summary.Observe(parsed.RootElement.GetProperty("data"));
            Interlocked.Increment(ref written);
            Interlocked.Add(ref bytesWritten, System.Text.Encoding.UTF8.GetByteCount(line) + System.Environment.NewLine.Length);
            Interlocked.Add(ref writerUsec, (Stopwatch.GetTimestamp() - began) * 1000000 / Stopwatch.Frequency);
        }
        try
        {
            while (!queue.IsCompleted)
            {
                if (queue.TryTake(out var item, 250))
                {
                    long writeStart = Stopwatch.GetTimestamp();
                    var envelope = (Envelope)item;
                    if (envelope.data is ProfileRecord profile)
                    {
                        Interlocked.Add(ref profileQueuedBytes, -profile.Json.Length * 2L);
                        try
                        {
                            using var document = JsonDocument.Parse(profile.Json);
                            if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.TryGetProperty("type", out var recordType) || recordType.ValueKind != JsonValueKind.String)
                                throw new JsonException("Profile record must be an object with a string type.");
                            envelope = envelope with { data = document.RootElement.Clone() };
                        }
                        catch (JsonException e)
                        {
                            envelope = envelope with { data = new { type = "telemetry_error", error = e.Message } };
                        }
                    }
                    else if (envelope.data is RichProfileRecord rich)
                    {
                        Interlocked.Add(ref profileQueuedBytes, -rich.Json.Length * 2L);
                        try
                        {
                            if (JsonNode.Parse(rich.Json) is not JsonObject node || node["type"]?.GetValueKind() != JsonValueKind.String)
                                throw new JsonException("Profile record must be an object with a string type.");
                            node["runtime"] = JsonSerializer.SerializeToNode(rich.Runtime);
                            node["runtime_snapshot_scope"] = rich.SnapshotScope;
                            if (rich.Context.ValueKind != JsonValueKind.Undefined && !node.ContainsKey("context"))
                                node["context"] = JsonNode.Parse(rich.Context.GetRawText());
                            envelope = envelope with { data = node };
                        }
                        catch (Exception e) when (e is JsonException or InvalidOperationException)
                        {
                            envelope = envelope with { data = new { type = "telemetry_error", error = e.Message } };
                        }
                    }
                    if (envelope.data is FrameWindow f)
                    {
                        var sorted = (double[])f.Values.Clone();
                        Array.Sort(sorted);
                        double total = f.Values.Sum();
                        envelope = envelope with { data = new { type = "metrics", frame_ms = f.Values, frame_context_ids = f.ContextIds, frame_state_ids = f.StateIds, context = f.Context,
                            fps = f.Values.Length * 1000.0 / total, frames = f.Values.Length, duration_ms = total,
                            p50_ms = sorted[(int)((sorted.Length - 1) * .50)], p95_ms = sorted[(int)((sorted.Length - 1) * .95)],
                            p99_ms = sorted[(int)((sorted.Length - 1) * .99)], max_ms = sorted[^1],
                            over_33_3_ms = f.Values.Count(v => v > 33.3), over_66_7_ms = f.Values.Count(v => v > 66.7) } };
                    }
                    string line = JsonSerializer.Serialize(envelope);
                    output.WriteLine(line);
                    using (var parsed = JsonDocument.Parse(line)) summary.Observe(parsed.RootElement.GetProperty("data"));
                    Interlocked.Increment(ref written);
                    Interlocked.Add(ref bytesWritten, System.Text.Encoding.UTF8.GetByteCount(line) + System.Environment.NewLine.Length);
                    Interlocked.Add(ref writerUsec, (Stopwatch.GetTimestamp() - writeStart) * 1000000 / Stopwatch.Frequency);
                }
                long now = Stopwatch.GetTimestamp();
                if (now - summaryAt >= Stopwatch.Frequency * 30) {
                    SaveSummary(summary);
                    summaryAt = now;
                }
                if (now - flushed >= Stopwatch.Frequency || queue.IsCompleted)
                {
                    long lost = Dropped;
                    if (lost != reportedDrops)
                    {
                        WriteAuxiliary(new { type = "records_dropped", count = lost - reportedDrops, total = lost, writer = WriterSnapshot() });
                        reportedDrops = lost;
                    }
                    double silence = (now - Interlocked.Read(ref lastFrame)) / (double)Stopwatch.Frequency;
                    if (silence >= 5 && !queue.IsCompleted) WriteAuxiliary(new { type = "main_thread_unresponsive",
                        seconds_without_frame = silence, context = ContextSnapshot(), writer = WriterSnapshot(), active_operations = ActiveOperations() });
                    var pending = ActiveOperations(5000);
                    if (pending.Length > 0 && !queue.IsCompleted) WriteAuxiliary(new { type = "operations_pending",
                        operations = pending, interpretation = "elapsed_wall_time_not_failure" });
                    output.Flush();
                    flushed = now;
                    if (output.BaseStream.Position >= 32 * 1024 * 1024)
                    {
                        output.Dispose();
                        output = OpenPart(++part);
                    }
                }
            }
        }
        catch (Exception e)
        {
            failure = e.ToString();
            // No recursive Godot logging from the writer.
            System.Console.Error.WriteLine("Harbor session log stopped: " + failure);
        }
        finally {
            try { output.Dispose(); SaveSummary(summary); } catch (Exception e) { failure = e.ToString(); }
        }
    }

    private void SaveSummary(SessionLogSummary summary) {
        string path = Path.Combine(Folder, "summary.json");
        string temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(summary.Export(WriterSnapshot(), Dropped, Failure), new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, path, true);
    }

    public void Close()
    {
        queue.CompleteAdding();
        if (!writer.Join(2000)) System.Console.Error.WriteLine("Harbor session log: shutdown drain exceeded 2s; queued records may be lost on process exit.");
    }
}
