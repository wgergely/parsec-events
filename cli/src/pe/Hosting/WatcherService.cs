using System.Text.RegularExpressions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Tomlyn;
using Tomlyn.Model;

namespace ParsecEventExecutor.Cli.Hosting;

public sealed class WatcherServiceOptions
{
    public string? ConfigPath { get; set; }
    public string? StateRoot { get; set; }
}

/// <summary>
/// Background service that tails the Parsec log, routes connect/disconnect events,
/// and dispatches recipes via the PowerShell module.
/// </summary>
public sealed class WatcherService : BackgroundService
{
    private readonly ILogger<WatcherService> _logger;
    private readonly WatcherServiceOptions _options;

    // Config values loaded from parsec-watcher.toml
    private string _parsecLogPath = "";
    private int _applyDelayMs = 3000;
    private int _gracePeriodMs = 10000;
    private int _pollIntervalMs = 1000;
    private Regex _connectPattern = null!;
    private Regex _disconnectPattern = null!;

    // Log tailing state
    private long _lastPosition;
    private long _lastKnownSize;

    // Session tracking
    private readonly Dictionary<string, DateTimeOffset> _activeSessions = new();
    private readonly List<PendingDispatch> _pendingConnects = new();
    private readonly List<PendingDispatch> _pendingDisconnects = new();

    public WatcherService(ILogger<WatcherService> logger, WatcherServiceOptions options)
    {
        _logger = logger;
        _options = options;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Parsec Event Watcher starting");

        LoadConfig();
        ResolveLogPath();

        _logger.LogInformation("Monitoring {LogPath}", _parsecLogPath);
        _logger.LogInformation("Apply delay: {Delay}ms, Grace period: {Grace}ms, Poll: {Poll}ms",
            _applyDelayMs, _gracePeriodMs, _pollIntervalMs);

        // Initialize file position to end of file
        if (File.Exists(_parsecLogPath))
        {
            _lastPosition = new FileInfo(_parsecLogPath).Length;
            _lastKnownSize = _lastPosition;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                PollLogFile();
                ProcessPendingDispatches();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in watcher loop");
            }

            await Task.Delay(_pollIntervalMs, stoppingToken);
        }

        _logger.LogInformation("Parsec Event Watcher stopped");
    }

    private void LoadConfig()
    {
        var configPath = _options.ConfigPath ?? FindConfigFile();

        if (!File.Exists(configPath))
        {
            _logger.LogWarning("Config file not found at {Path}, using defaults", configPath);
            _connectPattern = new Regex(@"\]\s+(.+#\d+)\s+connected\.\s*$", RegexOptions.Compiled);
            _disconnectPattern = new Regex(@"\]\s+(.+#\d+)\s+disconnected\.\s*$", RegexOptions.Compiled);
            return;
        }

        _logger.LogInformation("Loading config from {Path}", configPath);
        var toml = File.ReadAllText(configPath);
        var model = Toml.ToModel(toml);

        if (model.TryGetValue("watcher", out var watcherObj) && watcherObj is TomlTable watcher)
        {
            if (watcher.TryGetValue("parsec_log_path", out var logPath))
                _parsecLogPath = logPath?.ToString() ?? "auto";
            if (watcher.TryGetValue("apply_delay_ms", out var delay))
                _applyDelayMs = Convert.ToInt32(delay);
            if (watcher.TryGetValue("grace_period_ms", out var grace))
                _gracePeriodMs = Convert.ToInt32(grace);
            if (watcher.TryGetValue("poll_interval_ms", out var poll))
                _pollIntervalMs = Convert.ToInt32(poll);
        }

        var connectStr = @"\]\s+(.+#\d+)\s+connected\.\s*$";
        var disconnectStr = @"\]\s+(.+#\d+)\s+disconnected\.\s*$";

        if (model.TryGetValue("patterns", out var patternsObj) && patternsObj is TomlTable patterns)
        {
            if (patterns.TryGetValue("connect", out var cp))
                connectStr = cp?.ToString() ?? connectStr;
            if (patterns.TryGetValue("disconnect", out var dp))
                disconnectStr = dp?.ToString() ?? disconnectStr;
        }

        _connectPattern = new Regex(connectStr, RegexOptions.Compiled);
        _disconnectPattern = new Regex(disconnectStr, RegexOptions.Compiled);
    }

    private string FindConfigFile()
    {
        // Look alongside the exe first, then in ProgramData
        var exeDir = AppContext.BaseDirectory;
        var local = Path.Combine(exeDir, "parsec-watcher.toml");
        if (File.Exists(local))
            return local;

        // Walk up to find repo root (development)
        var candidate = exeDir;
        for (var i = 0; i < 8; i++)
        {
            var parent = Directory.GetParent(candidate)?.FullName;
            if (parent is null) break;

            var repoConfig = Path.Combine(parent, "parsec-watcher.toml");
            if (File.Exists(repoConfig))
                return repoConfig;

            candidate = parent;
        }

        var programData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "ParsecEventExecutor", "parsec-watcher.toml");

        return programData;
    }

    private void ResolveLogPath()
    {
        if (!string.IsNullOrEmpty(_parsecLogPath) && _parsecLogPath != "auto")
            return;

        // Auto-detect Parsec log: per-machine first, then per-user
        var candidates = new[]
        {
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "Parsec", "log.txt"),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Parsec", "log.txt")
        };

        foreach (var path in candidates)
        {
            if (File.Exists(path))
            {
                _parsecLogPath = path;
                return;
            }
        }

        _parsecLogPath = candidates[0];
        _logger.LogWarning("Parsec log not found, will monitor {Path}", _parsecLogPath);
    }

    private void PollLogFile()
    {
        if (!File.Exists(_parsecLogPath))
            return;

        var fileInfo = new FileInfo(_parsecLogPath);
        var currentSize = fileInfo.Length;

        // Detect log rotation (file got smaller)
        if (currentSize < _lastKnownSize)
        {
            _logger.LogInformation("Log file rotated, resetting position");
            _lastPosition = 0;
        }
        _lastKnownSize = currentSize;

        if (_lastPosition >= currentSize)
            return;

        using var stream = new FileStream(_parsecLogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        stream.Seek(_lastPosition, SeekOrigin.Begin);

        using var reader = new StreamReader(stream);
        string? line;
        while ((line = reader.ReadLine()) is not null)
        {
            RouteEvent(line);
        }

        _lastPosition = stream.Position;
    }

    private void RouteEvent(string line)
    {
        var connectMatch = _connectPattern.Match(line);
        if (connectMatch.Success)
        {
            var username = connectMatch.Groups[1].Value;
            _logger.LogInformation("Connect detected: {Username}", username);

            // Cancel any pending disconnects for this user
            _pendingDisconnects.RemoveAll(d => d.Username == username);

            // Dedup: cancel any existing pending connect for this user
            _pendingConnects.RemoveAll(d => d.Username == username);

            // Track session
            _activeSessions[username] = DateTimeOffset.UtcNow;

            // Queue connect dispatch with delay
            _pendingConnects.Add(new PendingDispatch
            {
                Username = username,
                EventType = "connect",
                DispatchAt = DateTimeOffset.UtcNow.AddMilliseconds(_applyDelayMs)
            });

            return;
        }

        var disconnectMatch = _disconnectPattern.Match(line);
        if (disconnectMatch.Success)
        {
            var username = disconnectMatch.Groups[1].Value;
            _logger.LogInformation("Disconnect detected: {Username}", username);

            // Cancel any pending connects for this user
            _pendingConnects.RemoveAll(d => d.Username == username);

            // Remove from active sessions
            _activeSessions.Remove(username);

            // Queue disconnect dispatch with grace period
            _pendingDisconnects.Add(new PendingDispatch
            {
                Username = username,
                EventType = "disconnect",
                DispatchAt = DateTimeOffset.UtcNow.AddMilliseconds(_gracePeriodMs)
            });
        }
    }

    private void ProcessPendingDispatches()
    {
        var now = DateTimeOffset.UtcNow;

        // Process expired connect dispatches
        var readyConnects = _pendingConnects.Where(d => d.DispatchAt <= now).ToList();
        foreach (var dispatch in readyConnects)
        {
            _pendingConnects.Remove(dispatch);
            DispatchRecipe(dispatch);
        }

        // Process expired disconnect dispatches (only if user hasn't reconnected)
        var readyDisconnects = _pendingDisconnects.Where(d => d.DispatchAt <= now).ToList();
        foreach (var dispatch in readyDisconnects)
        {
            _pendingDisconnects.Remove(dispatch);

            // Skip if user reconnected during grace period
            if (_activeSessions.ContainsKey(dispatch.Username))
            {
                _logger.LogInformation("Skipping disconnect dispatch for {Username} — reconnected during grace period",
                    dispatch.Username);
                continue;
            }

            DispatchRecipe(dispatch);
        }
    }

    private void DispatchRecipe(PendingDispatch dispatch)
    {
        _logger.LogInformation("Dispatching {EventType} recipe for {Username}",
            dispatch.EventType, dispatch.Username);

        // TODO: Phase 5b — use SessionBridge to dispatch via Task Scheduler
        // For now, invoke directly (works when running in user session, not as service)
        try
        {
            using var host = new PowerShellHost(logger: null);
            var recipes = host.GetRecipes();

            // Find matching recipe by event_type and optional username
            foreach (var recipe in recipes)
            {
                var eventType = recipe.Properties["event_type"]?.Value?.ToString();
                var username = recipe.Properties["username"]?.Value?.ToString();
                var recipeName = recipe.Properties["name"]?.Value?.ToString();

                if (eventType != dispatch.EventType)
                    continue;

                if (!string.IsNullOrEmpty(username) && username != dispatch.Username)
                    continue;

                _logger.LogInformation("Matched recipe: {RecipeName}", recipeName);

                if (recipeName is not null)
                {
                    host.InvokeRecipe(recipeName, _options.StateRoot);
                    _logger.LogInformation("Recipe '{RecipeName}' dispatched successfully", recipeName);
                }

                return;
            }

            // No matching recipe — for disconnect, try restoring default profile
            if (dispatch.EventType == "disconnect")
            {
                TryRestoreDefaultProfile(host);
            }
            else
            {
                _logger.LogWarning("No matching recipe for {EventType} event from {Username}",
                    dispatch.EventType, dispatch.Username);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to dispatch recipe for {EventType} event from {Username}",
                dispatch.EventType, dispatch.Username);
        }
    }

    private void TryRestoreDefaultProfile(PowerShellHost host)
    {
        try
        {
            var stateResults = host.GetExecutorState(_options.StateRoot);
            if (stateResults.Count == 0) return;

            var state = PsObjectHelpers.UnwrapToDictionary(stateResults[0]);
            var defaultProfile = state["default_profile"]?.ToString();

            if (string.IsNullOrEmpty(defaultProfile))
            {
                _logger.LogWarning("No disconnect recipe and no default profile configured");
                return;
            }

            _logger.LogInformation("No disconnect recipe — restoring default profile '{Profile}'", defaultProfile);

            var args = new Dictionary<string, object?>
            {
                ["snapshot_name"] = defaultProfile
            };

            host.InvokeIngredient("display.snapshot", operation: "reset", arguments: args, stateRoot: _options.StateRoot);
            _logger.LogInformation("Default profile '{Profile}' restored successfully", defaultProfile);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to restore default profile");
        }
    }

    private sealed class PendingDispatch
    {
        public required string Username { get; init; }
        public required string EventType { get; init; }
        public required DateTimeOffset DispatchAt { get; set; }
    }
}
