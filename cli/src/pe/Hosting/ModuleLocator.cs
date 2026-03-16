namespace ParsecEventExecutor.Cli.Hosting;

/// <summary>
/// Resolves the path to the ParsecEventExecutor PowerShell module
/// using the standard .NET co-location pattern.
/// </summary>
public static class ModuleLocator
{
    private const string ModuleName = "ParsecEventExecutor";
    private const string ManifestFile = "ParsecEventExecutor.psd1";

    /// <summary>
    /// Locates the PowerShell module directory. Searches:
    /// 1. Installed/published layout: {exeDir}/Module/ParsecEventExecutor/
    /// 2. Development layout: {repoRoot}/src/ParsecEventExecutor/
    /// </summary>
    public static string GetModulePath()
    {
        var baseDir = AppContext.BaseDirectory;

        // Installed/published layout: Module/ sits alongside pe.exe
        var installedPath = Path.Combine(baseDir, "Module", ModuleName);
        if (File.Exists(Path.Combine(installedPath, ManifestFile)))
            return installedPath;

        // Development layout: exe is in cli/src/pe/bin/{Config}/{TFM}/{RID}/
        // Module is in src/ParsecEventExecutor/
        // Walk up to find the repo root by looking for the src/ directory
        var candidate = baseDir;
        for (var i = 0; i < 8; i++)
        {
            var parent = Directory.GetParent(candidate)?.FullName;
            if (parent is null)
                break;

            var devPath = Path.Combine(parent, "src", ModuleName);
            if (File.Exists(Path.Combine(devPath, ManifestFile)))
                return devPath;

            candidate = parent;
        }

        throw new FileNotFoundException(
            $"ParsecEventExecutor module not found. Searched:\n" +
            $"  {Path.Combine(installedPath, ManifestFile)}\n" +
            $"  (walked up from {baseDir} looking for src/{ModuleName}/{ManifestFile})");
    }
}
