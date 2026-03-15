namespace ParsecEventExecutor;

public sealed class WindowCapture {
    public long Handle { get; set; }
    public long OwnerHandle { get; set; }
    public uint ProcessId { get; set; }
    public string ProcessName { get; set; }
    public string Title { get; set; }
    public string ClassName { get; set; }
    public bool IsVisible { get; set; }
    public bool IsMinimized { get; set; }
    public bool IsCloaked { get; set; }
    public bool IsShellWindow { get; set; }
    public bool IsOnInputDesktop { get; set; }
    public bool IsOnCurrentVirtualDesktop { get; set; }
    public long ExtendedStyle { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
}
