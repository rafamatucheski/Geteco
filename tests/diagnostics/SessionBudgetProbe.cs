using Godot;
using System;
using System.IO;
using System.Text.Json;

public partial class SessionBudgetProbe : Node
{
    public override void _Ready()
    {
        // Separate sink: no registration as OS logger and no interference with real sessions.
        var sink = new SessionLogSink(ProjectSettings.GlobalizePath("user://session-budget-tests"));
        sink.Record(new { type = "session_start", schema = 5 });
        sink.Profile("42"); // valid JSON, invalid profile shape; writer must recover.
        sink.Profile(new string('x', 2 * 1024 * 1024 + 1)); // explicit per-record limit.
        string payload = JsonSerializer.Serialize(new { type = "fixture_pressure", payload = new string('x', 1024 * 1024) });
        for (int i = 0; i < 200; i++) sink.Profile(payload);
        sink.Record(new { type = "session_end", remaining_frame_ms = Array.Empty<double>() });
        sink.Close();
        if (sink.Failure.Length != 0 || sink.Dropped < 2) throw new Exception("Budget did not reject bounded pressure correctly: " + sink.Failure);
        using var summary = JsonDocument.Parse(File.ReadAllText(Path.Combine(sink.Folder, "summary.json")));
        var data = summary.RootElement;
        if (!data.GetProperty("normal_end_seen").GetBoolean() || data.GetProperty("events").GetProperty("telemetry_error").GetInt32() != 1)
            throw new Exception("Malformed profile shape must be recoverable and session must close normally.");
        if (data.GetProperty("events").GetProperty("profile_record_oversize").GetInt32() != 1)
            throw new Exception("Oversize profile payload must be explicit.");
        GD.Print("PASS bounded profile payload pressure, oversize rejection, malformed-shape recovery and summary closure: ", sink.Folder);
        GetTree().Quit();
    }
}
