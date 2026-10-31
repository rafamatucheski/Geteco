using System;
using System.Runtime.InteropServices;

// Adaptador Direct2D pequeno e confinado à thread. Só buffers de pixel próprios vêm
// do Godot; nenhum objeto do motor nem dispositivo de render é usado nesta thread.
internal sealed class LoadingCanvas : IDisposable
{
    private nint factory, target;
    private readonly BeginDraw begin;
    private readonly EndDraw end;
    private readonly Clear clear;
    private readonly DrawBitmap draw;
    private readonly CreateBitmap create;
    private readonly ResizeTarget resize;

    public LoadingCanvas(nint window, int width, int height)
    {
        try {
            var iid = new Guid("06152247-6f50-465a-9245-118bfd3b6007");
            Check(D2D1CreateFactory(0, ref iid, 0, out factory));
            // Hardware rendering, 96 DPI: coordinates below are physical pixels.
            var properties = new TargetProperties { Type = 1, DpiX = 96, DpiY = 96 };
            var hwnd = new WindowProperties { Window = window, Size = new Size(width, height) };
            Check(Method<CreateTarget>(factory, 14)(factory, ref properties, ref hwnd, out target));
            begin = Method<BeginDraw>(target, 48);
            end = Method<EndDraw>(target, 49);
            clear = Method<Clear>(target, 47);
            draw = Method<DrawBitmap>(target, 26);
            create = Method<CreateBitmap>(target, 4);
            resize = Method<ResizeTarget>(target, 58);
        } catch { Dispose(); throw; }
    }

    public nint Upload(int width, int height, nint pixels)
    {
        var properties = new BitmapProperties { Format = 87, AlphaMode = 1, DpiX = 96, DpiY = 96 };
        Check(create(target, new Size(width, height), pixels, (uint)(width * 4), ref properties, out var bitmap));
        return bitmap;
    }
    public void Update(nint bitmap, nint pixels, int width) =>
        Check(Method<CopyPixels>(bitmap, 10)(bitmap, 0, pixels, (uint)(width * 4)));
    public void Resize(int width, int height)
    {
        var size = new Size(width, height);
        Check(resize(target, ref size));
    }
    public void Begin()
    {
        begin(target);
        var background = new Colour { R = 16 / 255f, G = 18 / 255f, B = 22 / 255f, A = 1 };
        clear(target, ref background);
    }
    public void Draw(nint bitmap, float x, float y, float width, float height, float opacity = 1)
    {
        var rect = new Rect { Left = x, Top = y, Right = x + width, Bottom = y + height };
        draw(target, bitmap, ref rect, opacity, 1, 0);
    }
    public void End() => Check(end(target, out _, out _));
    public void Dispose() { Release(ref target); Release(ref factory); }
    public static void Release(ref nint value) { if (value != 0) { Marshal.Release(value); value = 0; } }
    private static void Check(int result) { if (result < 0) Marshal.ThrowExceptionForHR(result); }
    private static T Method<T>(nint instance, int slot) where T : Delegate =>
        Marshal.GetDelegateForFunctionPointer<T>(Marshal.ReadIntPtr(Marshal.ReadIntPtr(instance), slot * IntPtr.Size));

    [StructLayout(LayoutKind.Sequential)] private struct Size
    { public uint Width, Height; public Size(int w, int h) { Width = (uint)w; Height = (uint)h; } }
    [StructLayout(LayoutKind.Sequential)] private struct TargetProperties
    { public uint Type, Format, AlphaMode; public float DpiX, DpiY; public uint Usage, MinimumLevel; }
    [StructLayout(LayoutKind.Sequential)] private struct WindowProperties
    { public nint Window; public Size Size; public uint Options; }
    [StructLayout(LayoutKind.Sequential)] private struct BitmapProperties
    { public uint Format, AlphaMode; public float DpiX, DpiY; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public float Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct Colour { public float R, G, B, A; }
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int CreateTarget(nint self, ref TargetProperties properties, ref WindowProperties window, out nint target);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int CreateBitmap(nint self, Size size, nint pixels, uint pitch, ref BitmapProperties properties, out nint bitmap);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int CopyPixels(nint self, nint rect, nint pixels, uint pitch);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int ResizeTarget(nint self, ref Size size);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate void BeginDraw(nint self);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int EndDraw(nint self, out ulong tag1, out ulong tag2);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate void Clear(nint self, ref Colour colour);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate void DrawBitmap(nint self, nint bitmap, ref Rect destination, float opacity, uint interpolation, nint source);
    [DllImport("d2d1", ExactSpelling = true)] private static extern int D2D1CreateFactory(uint type, ref Guid iid, nint options, out nint factory);
}
