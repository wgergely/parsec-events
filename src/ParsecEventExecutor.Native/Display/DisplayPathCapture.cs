namespace ParsecEventExecutor;

public sealed class DisplayPathCapture {
    public string AdapterKey { get; set; }
    public uint SourceId { get; set; }
    public uint TargetId { get; set; }
    public string SourceDeviceName { get; set; }
    public string MonitorFriendlyName { get; set; }
    public string MonitorDevicePath { get; set; }
    public string AdapterDevicePath { get; set; }
    public bool IsActive { get; set; }
    public bool TargetAvailable { get; set; }
    public uint PathFlags { get; set; }
    public uint SourceStatusFlags { get; set; }
    public uint TargetStatusFlags { get; set; }
    public int Rotation { get; set; }
    public int Scaling { get; set; }
    public int OutputTechnology { get; set; }
    public int ScanLineOrdering { get; set; }
    public uint RefreshRateNumerator { get; set; }
    public uint RefreshRateDenominator { get; set; }
    public bool HasSourceMode { get; set; }
    public uint SourceWidth { get; set; }
    public uint SourceHeight { get; set; }
    public int SourcePositionX { get; set; }
    public int SourcePositionY { get; set; }
    public int PixelFormat { get; set; }
    public bool HasTargetMode { get; set; }
    public uint TargetWidth { get; set; }
    public uint TargetHeight { get; set; }
    public ulong PixelRate { get; set; }
}
