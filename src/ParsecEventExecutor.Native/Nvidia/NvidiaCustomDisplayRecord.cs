namespace ParsecEventExecutor;

public sealed class NvidiaCustomDisplayRecord {
    public uint Width { get; set; }
    public uint Height { get; set; }
    public uint Depth { get; set; }
    public int ColorFormat { get; set; }
    public float RefreshRateHz { get; set; }
    public uint TimingStatus { get; set; }
    public bool HardwareModeSetOnly { get; set; }
}
