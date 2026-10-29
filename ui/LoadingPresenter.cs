using Godot;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;

// Windows presentation only. The game, resources and scene tree stay on Godot's
// main thread. An owned, non-activating window has its own draw loop, so a synchronous
// world constructor cannot stop the loading artwork. No Godot API runs there.
public partial class LoadingPresenter : Node
{
    private Presenter presenter;
    private Control cover;
    private CanvasLayer curtain;
    private bool recoveredFailure;
    private bool fading;

    public bool Begin(Control control, Godot.Collections.Array<int> order, byte[] titleFont, byte[] textFont)
    {
        if (!OperatingSystem.IsWindows() || DisplayServer.GetName() == "headless") return false;
        cover = control;
        curtain = GetParent() as CanvasLayer;
        var parent = (nint)DisplayServer.WindowGetNativeHandle(DisplayServer.HandleType.WindowHandle);
        if (parent == 0) return false;
        presenter = new Presenter(parent, order.ToArray(), titleFont, textFont);
        SetProcess(true);
        return true;
    }

    // Finish all Vulkan texture readbacks before creating the independent D3D
    // device. Concurrent driver initialization/readback can lock startup.
    public void StartPresentation() => presenter?.Start();

    // Called exclusively on Godot's main thread. Transfer owned bytes, never a
    // Texture/Image/Node reference, to the presenter thread.
    public bool AddImage(int index, Texture2D texture)
    {
        if (presenter == null || presenter.Failure != null) return false;
        try {
            using var image = texture.GetImage();
            if (image == null || (image.IsCompressed() && image.Decompress() != Error.Ok))
                throw new InvalidOperationException("Loading image decompression failed");
            image.Convert(Image.Format.Rgba8);
            var bytes = image.GetData();
            if (bytes.Length != image.GetWidth() * image.GetHeight() * 4)
                throw new InvalidOperationException("Invalid loading image size");
            presenter.Images.Enqueue(new Pixels(index, image.GetWidth(), image.GetHeight(), bytes));
            return true;
        } catch (Exception error) { presenter.Fail(error.Message); return false; }
    }

    public bool IsReady() => presenter?.Ready == true;
    public bool HasFailed() => presenter?.Failure != null;
    public void SetProgress(double value) { if (presenter != null) Volatile.Write(ref presenter.Progress, Math.Clamp(value, 0, 1)); }
    public void FadeOut(double seconds) { fading = true; presenter?.Fade(seconds); }
    public override void _Process(double delta)
    {
        if (presenter == null || !IsInstanceValid(cover)) return;
        if (presenter.Failure != null && !recoveredFailure) {
            foreach (var child in cover.GetChildren()) if (child is CanvasItem visual) visual.Show();
            cover.GetNodeOrNull<Control>("Artwork")?.SetProcess(true);
            GD.PushWarning("Loading presentation fallback: " + presenter.Failure);
            recoveredFailure = true;
        }
        if (presenter.Ready && !fading && !recoveredFailure)
            foreach (var child in cover.GetChildren())
                if (child is CanvasItem visual && visual.Visible == presenter.Shown) visual.Visible = !presenter.Shown;
        Volatile.Write(ref presenter.Opacity, curtain != null && curtain.Visible && cover.IsVisibleInTree() ? cover.Modulate.A : 0);
    }
    public Godot.Collections.Dictionary Snapshot()
    {
        var frames = presenter?.Intervals.ToArray() ?? Array.Empty<double>();
        var sorted = frames.OrderBy(x => x).ToArray();
        var allFrames = presenter?.PresentationIntervals.ToArray() ?? Array.Empty<double>();
        var allSorted = allFrames.OrderBy(x => x).ToArray();
        double allPercentile(double fraction) => allSorted.Length == 0 ? 0 : allSorted[(int)((allSorted.Length - 1) * fraction)];
        double percentile(double fraction) => sorted.Length == 0 ? 0 : sorted[(int)((sorted.Length - 1) * fraction)];
        var total = frames.Sum();
        return new Godot.Collections.Dictionary {
            ["backend"] = "Direct2D hardware / independent presentation thread",
            ["width"] = presenter?.Width ?? 0, ["height"] = presenter?.Height ?? 0,
            ["animation_seconds"] = presenter == null ? 0 : Volatile.Read(ref presenter.AnimationTime),
            ["displayed_progress"] = presenter == null ? 0 : Volatile.Read(ref presenter.DisplayedProgress),
            ["target_progress"] = presenter == null ? 0 : Volatile.Read(ref presenter.Progress),
            ["visibility"] = new Godot.Collections.Dictionary {
                ["ready"] = presenter?.Ready == true, ["shown"] = presenter?.Shown == true,
                ["opacity"] = presenter == null ? 0 : Volatile.Read(ref presenter.Opacity),
                ["parent_visible"] = presenter?.ParentVisible == true,
                ["parent_foreground"] = presenter?.ParentForeground == true,
                ["parent_minimized"] = presenter?.ParentMinimized == true
            },
            ["godot_window_size"] = DisplayServer.WindowGetSize().ToString(),
            ["frames"] = frames.Length, ["seconds"] = total / 1000,
            ["including_fade"] = new Godot.Collections.Dictionary {
                ["frames"] = allFrames.Length, ["fps"] = allFrames.Sum() > 0 ? allFrames.Length * 1000 / allFrames.Sum() : 0,
                ["p95_ms"] = allPercentile(.95), ["p99_ms"] = allPercentile(.99),
                ["max_ms"] = allSorted.Length == 0 ? 0 : allSorted[^1],
                ["over_66_7_ms"] = allFrames.Count(x => x > 66.7), ["intervals_ms"] = allFrames
            },
            ["fps"] = total > 0 ? frames.Length * 1000 / total : 0,
            ["p50_ms"] = percentile(.5), ["p95_ms"] = percentile(.95), ["p99_ms"] = percentile(.99),
            ["max_ms"] = sorted.Length == 0 ? 0 : sorted[^1],
            ["over_33_3_ms"] = frames.Count(x => x > 33.3), ["over_66_7_ms"] = frames.Count(x => x > 66.7),
            ["intervals_ms"] = frames, ["failure"] = presenter?.Failure ?? "",
            ["scope"] = "Opaque loading presentation; completed Direct2D EndDraw calls, not gameplay frames or GPU/compositor timings"
        };
    }
    // Reparenting the curtain during the menu/world handoff exits the tree
    // temporarily. Only actual destruction may stop presentation.
    public override void _Notification(int what) { if (what == NotificationPredelete) presenter?.Stop(); }

    private sealed record Pixels(int Index, int Width, int Height, byte[] Bytes);
    private sealed class Bitmap : IDisposable
    {
        public nint Handle;
        public int Width, Height;
        public Bitmap(Pixels pixels, LoadingCanvas canvas)
        {
            Width = pixels.Width; Height = pixels.Height;
            var data = pixels.Bytes;
            // Direct2D expects premultiplied BGRA, including transparent edges.
            for (var i = 0; i < data.Length; i += 4) {
                var red = data[i];
                var alpha = data[i + 3];
                data[i] = (byte)(data[i + 2] * alpha / 255);
                data[i + 1] = (byte)(data[i + 1] * alpha / 255);
                data[i + 2] = (byte)(red * alpha / 255);
            }
            var pinned = GCHandle.Alloc(data, GCHandleType.Pinned);
            try { Handle = canvas.Upload(Width, Height, pinned.AddrOfPinnedObject()); }
            finally { pinned.Free(); }
        }
        public void Dispose() => LoadingCanvas.Release(ref Handle);
    }
    private sealed class Presenter
    {
        private static readonly Native.WindowProc WindowCallback = WindowProcedure;
        private static readonly ConcurrentDictionary<nint, Presenter> Windows = new();
        public readonly ConcurrentQueue<Pixels> Images = new();
        public readonly ConcurrentQueue<double> Intervals = new();
        public readonly ConcurrentQueue<double> PresentationIntervals = new();
        public volatile bool Ready;
        public volatile string Failure;
        public double Progress, Opacity;
        private readonly nint parent;
        private readonly string className = "GetecoLoadingPresenter_" + Guid.NewGuid().ToString("N");
        public int Width => Volatile.Read(ref width);
        public int Height => Volatile.Read(ref height);
        private readonly int[] order;
        private readonly byte[] titleFontBytes, textFontBytes;
        private readonly Dictionary<int, Bitmap> bitmaps = new();
        private Thread thread;
        private volatile bool stopped;
        private long fadeAt;
        private double fadeSeconds;
        private nint window, buffer, graphics, titleFont, textFont, brush, trackBrush, accentBrush, format, overlay;
        private LoadingCanvas canvas;
        private GCHandle overlayPin;
        private int overlayPercent = -1, overlayWidth, overlayHeight;
        private static readonly string[] Percentages = Enumerable.Range(0, 101).Select(x => x + "%").ToArray();
        private readonly List<nint> fontFamilies = new();
        private readonly List<nint> fontCollections = new();
        private readonly List<GCHandle> fontPins = new();
        private int width, height;
        private long previousTick, previousPaint, previousAnyPaint;
        public double AnimationTime, DisplayedProgress;
        public volatile bool Shown;
        public volatile bool ParentVisible, ParentForeground, ParentMinimized;
        private int left = int.MinValue, top = int.MinValue;
        public Presenter(nint parentHandle, int[] sequence, byte[] displayFont, byte[] bodyFont)
        { parent = parentHandle; order = sequence; titleFontBytes = displayFont; textFontBytes = bodyFont; }
        public void Start()
        {
            thread = new Thread(Run) { IsBackground = true, Name = "Geteco loading presentation" };
            thread.Start();
        }
        public void Fail(string reason) { Failure = reason; stopped = true; }
        public void Fade(double seconds) { fadeSeconds = Math.Max(.01, seconds); Interlocked.Exchange(ref fadeAt, Stopwatch.GetTimestamp()); }
        public void Stop() { stopped = true; thread?.Join(250); }
        private static double Seconds(long ticks) => (double)ticks / Stopwatch.Frequency;
        private void Run()
        {
            nuint token = 0;
            try {
                // Godot can set DPI awareness on its main thread. Match its window
                // before creating a child or reading client coordinates here.
                Native.SetThreadDpiAwarenessContext(Native.GetWindowDpiAwarenessContext(parent));
                var input = new Native.GdiStartup { Version = 1 };
                if (Native.GdiplusStartup(out token, ref input, 0) != 0) throw new InvalidOperationException("GDI+ startup failed");
                var klass = new Native.WindowClass { Proc = WindowCallback, Instance = Native.GetModuleHandleW(null), Name = className };
                if (Native.RegisterClassW(ref klass) == 0)
                    throw new InvalidOperationException("Loading window class registration failed: " + Marshal.GetLastWin32Error());
                Native.GetClientRect(parent, out var rect);
                var origin = new Native.Point();
                Native.ClientToScreen(parent, ref origin);
                // Godot's host manifest lacks Windows 8 compatibility, which
                // forbids layered CHILD windows. An owned popup supports alpha
                // without modifying the engine or entering Alt-Tab/taskbar.
                window = Native.CreateWindowExW(0x080800a0, klass.Name, "", 0x80000000, origin.X, origin.Y, rect.Right, rect.Bottom, parent, 0, klass.Instance, 0);
                if (window == 0) throw new InvalidOperationException("Loading owned window creation failed: " + Marshal.GetLastWin32Error());
                Windows[window] = this;
                canvas = new LoadingCanvas(window, rect.Right, rect.Bottom);
                width = rect.Right; height = rect.Bottom;
                titleFont = CreateFont(titleFontBytes, 32);
                textFont = CreateFont(textFontBytes, 16);
                Native.GdipCreateSolidFill(0xffeee9df, out brush);
                Native.GdipCreateSolidFill(0xff5a5b58, out trackBrush);
                Native.GdipCreateSolidFill(0xffeee0bd, out accentBrush);
                Native.GdipStringFormatGetGenericTypographic(out format);
                Native.GdipSetStringFormatAlign(format, 0);
                long next = Stopwatch.GetTimestamp();
                while (!stopped && Native.IsWindow(parent)) {
                    while (Native.PeekMessageW(out var message, 0, 0, 0, 1)) {
                        Native.TranslateMessage(ref message);
                        Native.DispatchMessageW(ref message);
                    }
                    if (Images.TryDequeue(out var pixels)) bitmaps[pixels.Index] = new Bitmap(pixels, canvas);
                    var now = Stopwatch.GetTimestamp();
                    if (now < next) { Thread.Sleep(1); continue; }
                    next += Stopwatch.Frequency / 60;
                    if (next < now) next = now + Stopwatch.Frequency / 60;
                    if (bitmaps.Count != order.Length) continue;
                    Native.GetClientRect(parent, out rect);
                    if (rect.Right <= 0 || rect.Bottom <= 0) { previousPaint = previousAnyPaint = 0; continue; }
                    var resized = width != rect.Right || height != rect.Bottom;
                    if (resized) {
                        canvas.Resize(rect.Right, rect.Bottom);
                        width = rect.Right; height = rect.Bottom;
                    }
                    origin = new Native.Point();
                    Native.ClientToScreen(parent, ref origin);
                    if (resized || left != origin.X || top != origin.Y) {
                        left = origin.X; top = origin.Y;
                        Native.SetWindowPos(window, 0, left, top, width, height, 0x0214);
                    }
                    var opacity = Math.Clamp(Volatile.Read(ref Opacity), 0, 1);
                    var fade = Interlocked.Read(ref fadeAt);
                    if (fade != 0) {
                        var amount = Math.Clamp(Seconds(now - fade) / fadeSeconds, 0, 1);
                        opacity = 1 - amount * amount * (3 - 2 * amount);
                        if (amount >= 1) break;
                    }
                    // Never put a loading overlay over an unrelated foreground
                    // application. Godot remains the focus/input owner.
                    ParentVisible = Native.IsWindowVisible(parent);
                    ParentMinimized = Native.IsIconic(parent);
                    ParentForeground = Native.GetForegroundWindow() == Native.GetAncestor(parent, 2);
                    if (opacity <= 0 || ParentMinimized || !ParentVisible || !ParentForeground) {
                        if (Shown) Native.ShowWindow(window, 0);
                        Shown = false; previousPaint = previousAnyPaint = previousTick = 0;
                        // Prepare the first frame even while the menu fades in.
                        if (!Ready) { Draw(0); Ready = true; }
                        continue;
                    }
                    // A delayed paint must not jump ahead through a crossfade.
                    var step = previousTick == 0 ? 0 : Math.Min(.05, Seconds(now - previousTick));
                    previousTick = now;
                    AnimationTime += step;
                    DisplayedProgress = Math.Min(Volatile.Read(ref Progress), DisplayedProgress + step * .9);
                    if (fade != 0) DisplayedProgress = 1;
                    Draw(AnimationTime);
                    Native.SetLayeredWindowAttributes(window, 0, (byte)Math.Round(opacity * 255), 2);
                    if (!Shown) { Native.ShowWindow(window, 4); Shown = true; }
                    Ready = true;
                    var painted = Stopwatch.GetTimestamp();
                    if (previousAnyPaint != 0 && PresentationIntervals.Count < 20000)
                        PresentationIntervals.Enqueue(Seconds(painted - previousAnyPaint) * 1000);
                    previousAnyPaint = painted;
                    if (opacity >= .999 && fade == 0) {
                        if (previousPaint != 0 && Intervals.Count < 20000) Intervals.Enqueue(Seconds(painted - previousPaint) * 1000);
                        previousPaint = painted;
                    } else previousPaint = 0;
                }
            } catch (Exception error) { Failure = error.Message; }
            finally {
                if (window != 0) { Windows.TryRemove(window, out _); Native.DestroyWindow(window); }
                Shown = false;
                Native.UnregisterClassW(className, Native.GetModuleHandleW(null));
                if (graphics != 0) Native.GdipDeleteGraphics(graphics);
                if (buffer != 0) Native.GdipDisposeImage(buffer);
                if (overlayPin.IsAllocated) overlayPin.Free();
                LoadingCanvas.Release(ref overlay);
                foreach (var bitmap in bitmaps.Values) bitmap.Dispose();
                canvas?.Dispose();
                if (titleFont != 0) Native.GdipDeleteFont(titleFont);
                if (textFont != 0) Native.GdipDeleteFont(textFont);
                foreach (var family in fontFamilies) Native.GdipDeleteFontFamily(family);
                foreach (var value in fontCollections) { var collection = value; Native.GdipDeletePrivateFontCollection(ref collection); }
                foreach (var pin in fontPins) if (pin.IsAllocated) pin.Free();
                if (brush != 0) Native.GdipDeleteBrush(brush);
                if (trackBrush != 0) Native.GdipDeleteBrush(trackBrush);
                if (accentBrush != 0) Native.GdipDeleteBrush(accentBrush);
                if (format != 0) Native.GdipDeleteStringFormat(format);
                if (token != 0) Native.GdiplusShutdown(token);
            }
        }
        private nint CreateFont(byte[] data, float size)
        {
            Native.GdipNewPrivateFontCollection(out var collection);
            fontCollections.Add(collection);
            var pin = GCHandle.Alloc(data, GCHandleType.Pinned);
            fontPins.Add(pin);
            Native.GdipPrivateAddMemoryFont(collection, pin.AddrOfPinnedObject(), data.Length);
            Native.GdipGetFontCollectionFamilyCount(collection, out var count);
            var families = new nint[count];
            Native.GdipGetFontCollectionFamilyList(collection, count, families, out _);
            if (count == 0 || Native.GdipCloneFontFamily(families[0], out var family) != 0)
                throw new InvalidOperationException("Loading font family allocation failed");
            fontFamilies.Add(family);
            for (var style = 0; style < 4; style++)
                if (Native.GdipCreateFont(family, size, style, 2, out var font) == 0) return font;
            throw new InvalidOperationException("Loading font creation failed");
        }
        private void Draw(double time)
        {
            canvas.Begin();
            const double hold = 6, crossfade = 1.4, cycle = hold + crossfade;
            var sequence = (int)(time / cycle);
            var local = time % cycle;
            var index = order[sequence % order.Length];
            DrawImage(bitmaps[index], index, local + (sequence == 0 ? 0 : crossfade), 1);
            if (local >= hold) {
                var incoming = order[(sequence + 1) % order.Length];
                var blend = (local - hold) / crossfade;
                DrawImage(bitmaps[incoming], incoming, local - hold, (float)(blend * blend * (3 - 2 * blend)));
            }
            var scale = Math.Min((float)width / 1280, (float)height / 720);
            EnsureOverlay(scale);
            UpdateOverlay();
            canvas.Draw(overlay, 0, height - overlayHeight, overlayWidth, overlayHeight);
            canvas.End();
        }
        // O texto era rasterizado em 1280x160 e esticado: em tela cheia 1080p/1440p
        // "HARBOR" ficava borrado. Agora o bitmap tem o tamanho real na tela (1:1) e
        // só é refeito quando a janela muda de escala; o custo continua sendo só
        // redesenhar quando o percentual inteiro muda.
        private void EnsureOverlay(float scale)
        {
            var w = Math.Max(1, (int)Math.Round(1280 * scale));
            var h = Math.Max(1, (int)Math.Round(160 * scale));
            if (buffer != 0 && w == overlayWidth && h == overlayHeight) return;
            if (graphics != 0) { Native.GdipDeleteGraphics(graphics); graphics = 0; }
            if (buffer != 0) { Native.GdipDisposeImage(buffer); buffer = 0; }
            if (overlayPin.IsAllocated) overlayPin.Free();
            LoadingCanvas.Release(ref overlay);
            overlayPin = GCHandle.Alloc(new byte[w * h * 4], GCHandleType.Pinned);
            if (Native.GdipCreateBitmapFromScan0(w, h, w * 4, 0xE200B, overlayPin.AddrOfPinnedObject(), out buffer) != 0)
                throw new InvalidOperationException("Loading text allocation failed");
            Native.GdipGetImageGraphicsContext(buffer, out graphics);
            Native.GdipSetPageUnit(graphics, 2);
            Native.GdipSetTextRenderingHint(graphics, 4);
            // O layout continua em unidades de 1280x720; a transformação leva ao pixel real.
            Native.GdipScaleWorldTransform(graphics, (float)w / 1280, (float)h / 160, 0);
            overlayWidth = w; overlayHeight = h;
            overlayPercent = -1;
        }
        private void UpdateOverlay()
        {
            var percent = (int)Math.Floor(DisplayedProgress * 100);
            if (overlayPercent == percent) return;
            overlayPercent = percent;
            Native.GdipGraphicsClear(graphics, 0);
            var titleRect = new Native.RectF { X = 48, Y = 30, Width = 300, Height = 44 };
            Native.GdipDrawString(graphics, "HARBOR", -1, titleFont, ref titleRect, format, brush);
            var statusRect = new Native.RectF { X = 48, Y = 77, Width = 170, Height = 24 };
            Native.GdipDrawString(graphics, "Carregando…", -1, textFont, ref statusRect, format, brush);
            var percentRect = new Native.RectF { X = 225, Y = 77, Width = 43, Height = 24 };
            Native.GdipSetStringFormatAlign(format, 2);
            Native.GdipDrawString(graphics, Percentages[percent], -1, textFont, ref percentRect, format, brush);
            Native.GdipSetStringFormatAlign(format, 0);
            Native.GdipFillRectangle(graphics, trackBrush, 48, 105, 220, 3);
            Native.GdipFillRectangle(graphics, accentBrush, 48, 105, 220 * percent / 100f, 3);
            Native.GdipFlush(graphics, 1);
            if (overlay == 0) overlay = canvas.Upload(overlayWidth, overlayHeight, overlayPin.AddrOfPinnedObject());
            else canvas.Update(overlay, overlayPin.AddrOfPinnedObject(), overlayWidth);
        }
        private void DrawImage(Bitmap bitmap, int index, double age, float opacity)
        {
            var progress = Math.Clamp(age / 8.8, 0, 1);
            var zoom = 1.06 + .06 * progress;
            var cover = Math.Max((double)width / bitmap.Width, (double)height / bitmap.Height) * zoom;
            var w = (float)(bitmap.Width * cover);
            var h = (float)(bitmap.Height * cover);
            var x = (float)((width - w) * .5 + (index % 2 == 0 ? 1 : -1) * width * .018 * (progress * 2 - 1));
            var y = (float)((height - h) * .5 + (index % 3 == 0 ? 1 : -1) * height * .012 * (progress * 2 - 1));
            canvas.Draw(bitmap.Handle, x, y, w, h, opacity);
        }
        private static nint WindowProcedure(nint hwnd, uint message, nuint wparam, nint lparam)
        {
            if (message == 0x84) return -1; // HTTRANSPARENT: input remains with Godot's modal cover.
            if (message == 0x14) return 1; // Double-buffered; no intermediate erase flash.
            if (message == 0x0F && Windows.ContainsKey(hwnd)) {
                Native.BeginPaint(hwnd, out var paint);
                Native.EndPaint(hwnd, ref paint);
                return 0;
            }
            return Native.DefWindowProcW(hwnd, message, wparam, lparam);
        }
    }

    private static class Native
    {
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate nint WindowProc(nint window, uint message, nuint wparam, nint lparam);
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct WindowClass {
            public uint Style; public WindowProc Proc; public int ClassExtra, WindowExtra; public nint Instance, Icon, Cursor, Background;
            public string Menu, Name;
        }
        [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] public struct RectF { public float X, Y, Width, Height; }
        [StructLayout(LayoutKind.Sequential)] public struct Message { public nint Window; public uint Id; public nuint Wparam; public nint Lparam; public uint Time; public int X, Y; public uint Private; }
        [StructLayout(LayoutKind.Sequential)] public struct Paint { public nint Dc; public int Erase; public Rect Rectangle; public int Restore, IncUpdate; [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public byte[] Reserved; }
        [StructLayout(LayoutKind.Sequential)] public struct GdiStartup { public uint Version; public nint Debug; public int SuppressThread, SuppressCodecs; }
        [DllImport("kernel32", CharSet = CharSet.Unicode)] public static extern nint GetModuleHandleW(string name);
        [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern ushort RegisterClassW(ref WindowClass klass);
        [DllImport("user32", CharSet = CharSet.Unicode)] public static extern bool UnregisterClassW(string name, nint instance);
        [DllImport("user32")] public static extern bool ClientToScreen(nint window, ref Point point);
        [DllImport("user32")] public static extern bool IsIconic(nint window);
        [DllImport("user32")] public static extern bool IsWindowVisible(nint window);
        [DllImport("user32")] public static extern nint GetForegroundWindow();
        [DllImport("user32")] public static extern nint GetAncestor(nint window, uint flags);
        [DllImport("user32", CharSet = CharSet.Unicode, SetLastError = true)] public static extern nint CreateWindowExW(uint extended, string klass, string title, uint style, int x, int y, int width, int height, nint parent, nint menu, nint instance, nint param);
        [DllImport("user32")] public static extern nint GetWindowDpiAwarenessContext(nint window);
        [DllImport("user32")] public static extern nint SetThreadDpiAwarenessContext(nint context);
        [DllImport("user32")] public static extern bool GetClientRect(nint window, out Rect rect);
        [DllImport("user32")] public static extern bool IsWindow(nint window);
        [DllImport("user32")] public static extern bool DestroyWindow(nint window);
        [DllImport("user32")] public static extern bool ShowWindow(nint window, int command);
        [DllImport("user32")] public static extern bool SetWindowPos(nint window, nint after, int x, int y, int w, int h, uint flags);
        [DllImport("user32")] public static extern bool SetLayeredWindowAttributes(nint window, uint colour, byte alpha, uint flags);
        [DllImport("user32")] public static extern bool PeekMessageW(out Message message, nint window, uint first, uint last, uint flags);
        [DllImport("user32")] public static extern bool TranslateMessage(ref Message message);
        [DllImport("user32")] public static extern nint DispatchMessageW(ref Message message);
        [DllImport("user32")] public static extern nint DefWindowProcW(nint window, uint message, nuint wparam, nint lparam);
        [DllImport("user32")] public static extern nint BeginPaint(nint window, out Paint paint);
        [DllImport("user32")] public static extern bool EndPaint(nint window, ref Paint paint);
        [DllImport("gdiplus")] public static extern int GdiplusStartup(out nuint token, ref GdiStartup input, nint output);
        [DllImport("gdiplus")] public static extern void GdiplusShutdown(nuint token);
        [DllImport("gdiplus")] public static extern int GdipCreateBitmapFromScan0(int width, int height, int stride, int format, nint data, out nint bitmap);
        [DllImport("gdiplus")] public static extern int GdipDisposeImage(nint image);
        [DllImport("gdiplus")] public static extern int GdipGetImageGraphicsContext(nint image, out nint graphics);
        [DllImport("gdiplus")] public static extern int GdipDeleteGraphics(nint graphics);
        [DllImport("gdiplus")] public static extern int GdipGraphicsClear(nint graphics, uint colour);
        [DllImport("gdiplus")] public static extern int GdipFlush(nint graphics, int intention);
        [DllImport("gdiplus")] public static extern int GdipSetPageUnit(nint graphics, int unit);
        [DllImport("gdiplus")] public static extern int GdipScaleWorldTransform(nint graphics, float sx, float sy, int order);
        [DllImport("gdiplus")] public static extern int GdipSetTextRenderingHint(nint graphics, int hint);
        [DllImport("gdiplus")] public static extern int GdipNewPrivateFontCollection(out nint collection);
        [DllImport("gdiplus")] public static extern int GdipDeletePrivateFontCollection(ref nint collection);
        [DllImport("gdiplus")] public static extern int GdipPrivateAddMemoryFont(nint collection, nint memory, int length);
        [DllImport("gdiplus")] public static extern int GdipGetFontCollectionFamilyCount(nint collection, out int count);
        [DllImport("gdiplus")] public static extern int GdipGetFontCollectionFamilyList(nint collection, int count, nint[] families, out int found);
        [DllImport("gdiplus")] public static extern int GdipCloneFontFamily(nint family, out nint clone);
        [DllImport("gdiplus")] public static extern int GdipDeleteFontFamily(nint family);
        [DllImport("gdiplus")] public static extern int GdipCreateFont(nint family, float size, int style, int unit, out nint font);
        [DllImport("gdiplus")] public static extern int GdipDeleteFont(nint font);
        [DllImport("gdiplus")] public static extern int GdipCreateSolidFill(uint colour, out nint brush);
        [DllImport("gdiplus")] public static extern int GdipDeleteBrush(nint brush);
        [DllImport("gdiplus")] public static extern int GdipStringFormatGetGenericTypographic(out nint format);
        [DllImport("gdiplus")] public static extern int GdipDeleteStringFormat(nint format);
        [DllImport("gdiplus")] public static extern int GdipSetStringFormatAlign(nint format, int align);
        [DllImport("gdiplus", CharSet = CharSet.Unicode)] public static extern int GdipDrawString(nint graphics, string text, int length, nint font, ref RectF layout, nint format, nint brush);
        [DllImport("gdiplus")] public static extern int GdipFillRectangle(nint graphics, nint brush, float x, float y, float width, float height);
    }
}
