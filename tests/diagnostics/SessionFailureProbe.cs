using Godot;
using System;
using System.Threading;

public partial class SessionFailureProbe : Node
{
    private int frames;
    public override void _Process(double delta)
    {
        frames++;
        if (frames == 1) throw new InvalidOperationException("DIAGNOSTICS_TEST managed exception marker");
        if (frames == 2)
        {
            GD.Print("DIAGNOSTICS_TEST managed callback recovered");
            var worker = new Thread(() => GD.Print("DIAGNOSTICS_TEST worker marker"));
            worker.Start();
            SetProcess(false);
        }
    }
}
