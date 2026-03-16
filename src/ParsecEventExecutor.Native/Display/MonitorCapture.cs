namespace ParsecEventExecutor;

public sealed class MonitorCapture {
    public string DeviceName { get; set; }
    public bool IsPrimary { get; set; }
    public int Left { get; set; }
    public int Top { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public int WorkLeft { get; set; }
    public int WorkTop { get; set; }
    public int WorkWidth { get; set; }
    public int WorkHeight { get; set; }
    public int Orientation { get; set; }
    public int BitsPerPel { get; set; }
    public int DisplayFrequency { get; set; }
    public uint EffectiveDpiX { get; set; }
    public uint EffectiveDpiY { get; set; }
    public bool HasEffectiveDpi { get; set; }
}
