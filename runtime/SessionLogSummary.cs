using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

// Writer-thread only. Bounded histograms/caches; never retains every frame of a long session.
internal sealed class SessionLogSummary
{
    private sealed class Stats {
        public long Frames, Over33, Over66;
        public double Total, Maximum;
        private readonly long[] histogram = new long[8192]; // upper bounds in 0.1 ms
        public void Add(double value) {
            Frames++; Total += value; Maximum = Math.Max(Maximum, value);
            if (value > 33.3) Over33++; if (value > 66.7) Over66++;
            histogram[Math.Clamp((int)Math.Ceiling(value * 10), 0, histogram.Length - 1)]++;
        }
        private double Quantile(double fraction) {
            long target = Math.Max(1, (long)Math.Ceiling(Frames * fraction)), seen = 0;
            for (int i = 0; i < histogram.Length; i++) {
                seen += histogram[i];
                if (seen >= target) return i == histogram.Length - 1 ? Maximum : i / 10.0;
            }
            return 0;
        }
        public object Export() => new { frames = Frames, duration_ms = Total, fps = Total > 0 ? Frames * 1000.0 / Total : 0,
            p50_ms = Quantile(.5), p95_ms = Quantile(.95), p99_ms = Quantile(.99), max_ms = Maximum,
            over_33_3_ms = Over33, over_66_7_ms = Over66,
            quantiles = "histogram_upper_bound_0.1ms; overflow_819.1ms_uses_maximum; use_reader_for_exact" };
    }
    private readonly Dictionary<string, long> events = new();
    private readonly Dictionary<int, JsonElement> contexts = new(), states = new();
    private readonly Dictionary<string, Stats> scenarios = new();
    private readonly List<JsonElement> incidents = new(), slowStages = new();
    private readonly Dictionary<string, long> errors = new();
    private JsonElement start;
    private bool ended;
    private long omitted;
    private static string Field(JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var found) ? found.ToString() : "unknown";
    private void Cache(Dictionary<int, JsonElement> cache, JsonElement data) {
        int id = data.GetProperty("id").GetInt32();
        cache[id] = data.Clone();
        if (cache.Count > 64) cache.Remove(cache.Keys.Min());
    }
    private void AddFrames(JsonElement data, string valuesName, string contextIdsName, string stateIdsName) {
        if (!data.TryGetProperty(valuesName, out var values)) return;
        int[] ids = data.TryGetProperty(contextIdsName, out var c) ? c.EnumerateArray().Select(x => x.GetInt32()).ToArray() : Array.Empty<int>();
        int[] runtimeIds = data.TryGetProperty(stateIdsName, out var r) ? r.EnumerateArray().Select(x => x.GetInt32()).ToArray() : Array.Empty<int>();
        int index = 0;
        foreach (var value in values.EnumerateArray()) {
            JsonElement world = default, state = default;
            if (index < ids.Length && contexts.TryGetValue(ids[index], out var cached)) world = cached.GetProperty("context");
            if (index < runtimeIds.Length) states.TryGetValue(runtimeIds[index], out state);
            string key = $"scene={Field(state,"scene")};region={Field(world,"region")};place={Field(world,"place")};driving={Field(world,"driving")};ready={Field(world,"world_ready")};focused={Field(state,"focused")};paused={Field(state,"paused")};resolution={Field(state,"resolution")};max_fps={Field(state,"max_fps")}";
            if (!scenarios.TryGetValue(key, out var stats)) {
                if (scenarios.Count >= 64) { omitted++; index++; continue; }
                stats = new Stats(); scenarios[key] = stats;
            }
            stats.Add(value.GetDouble()); index++;
        }
    }
    private static void Top(List<JsonElement> list, JsonElement data, string metric) {
        list.Add(data.Clone());
        list.Sort((a,b) => b.GetProperty(metric).GetDouble().CompareTo(a.GetProperty(metric).GetDouble()));
        if (list.Count > 12) list.RemoveAt(list.Count - 1);
    }
    public void Observe(JsonElement data) {
        string kind = Field(data, "type");
        if (events.ContainsKey(kind) || events.Count < 128) events[kind] = events.GetValueOrDefault(kind) + 1;
        else omitted++;
        switch (kind) {
            case "session_start": start = data.Clone(); break;
            case "context_update": Cache(contexts, data); break;
            case "runtime_state_changed": Cache(states, data); break;
            case "metrics": AddFrames(data, "frame_ms", "frame_context_ids", "frame_state_ids"); break;
            case "session_end": ended = true; AddFrames(data, "remaining_frame_ms", "remaining_context_ids", "remaining_state_ids"); break;
            case "frame_spike": Top(incidents, data, "frame_ms"); break;
            case "operation_end": Top(slowStages, data, "duration_ms"); break;
            case "error":
            case "stderr":
            case "telemetry_error":
            case "managed_unhandled_exception":
            case "managed_unobserved_task_exception":
                string key = kind + ":" + Field(data, "source_key");
                if (errors.ContainsKey(key) || errors.Count < 256) errors[key] = errors.GetValueOrDefault(key) + 1;
                else omitted++;
                break;
        }
    }
    public object Export(object writer, long dropped, string failure) => new {
        schema = 5, generated_utc = DateTime.UtcNow, normal_end_seen = ended,
        session = start.ValueKind == JsonValueKind.Undefined ? (object)null : start,
        events, scenarios = scenarios.Select(x => new { scenario = x.Key, metrics = x.Value.Export() }).ToArray(),
        errors_by_source = errors, largest_incidents = incidents, slowest_completed_stages = slowStages,
        summary_omitted = omitted, records_dropped = dropped, writer_failure = failure, writer,
        interpretation = "correlation_not_proven_cause; missing_end_may_be_active_crash_or_write_failure; partial_snapshot_every_30s"
    };
}
