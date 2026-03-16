using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using Microsoft.Extensions.Logging;

namespace ParsecEventExecutor.Cli.Hosting;

/// <summary>
/// Manages a PowerShell runspace with the ParsecEventExecutor module loaded.
/// Provides typed methods for invoking module commands.
/// </summary>
public sealed class PowerShellHost : IDisposable
{
    private readonly Runspace _runspace;
    private readonly string _modulePath;
    private readonly ILogger<PowerShellHost>? _logger;
    private bool _disposed;

    public PowerShellHost(string? modulePath = null, ILogger<PowerShellHost>? logger = null)
    {
        _modulePath = modulePath ?? ModuleLocator.GetModulePath();
        _logger = logger;

        var iss = InitialSessionState.CreateDefault2();
        _runspace = RunspaceFactory.CreateRunspace(iss);
        _runspace.Open();

        ImportModule();
    }

    private void ImportModule()
    {
        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = _runspace;
        ps.AddCommand("Import-Module")
          .AddParameter("Name", _modulePath)
          .AddParameter("Force", true);

        ps.Invoke();
        ThrowOnErrors(ps, "Failed to import ParsecEventExecutor module");
    }

    /// <summary>
    /// Invokes a PowerShell command with optional parameters and returns raw PSObject results.
    /// </summary>
    public Collection<PSObject> Invoke(string command, Dictionary<string, object?>? parameters = null)
    {
        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = _runspace;
        ps.AddCommand(command);

        if (parameters is not null)
        {
            foreach (var (key, value) in parameters)
            {
                if (value is true)
                    ps.AddParameter(key);
                else if (value is not null and not false)
                    ps.AddParameter(key, value);
            }
        }

        var results = ps.Invoke();
        DrainStreams(ps);
        ThrowOnErrors(ps, $"Command '{command}' failed");

        return results;
    }

    public Collection<PSObject> GetRecipes(string? nameOrPath = null)
    {
        var parameters = new Dictionary<string, object?>
        {
            ["NameOrPath"] = nameOrPath ?? "*"
        };
        return Invoke("Get-ParsecRecipe", parameters);
    }

    public Collection<PSObject> InvokeRecipe(string nameOrPath, string? stateRoot = null, bool whatIf = false)
    {
        var parameters = new Dictionary<string, object?>
        {
            ["NameOrPath"] = nameOrPath
        };
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;
        if (whatIf) parameters["WhatIf"] = true;

        return Invoke("Invoke-ParsecRecipe", parameters);
    }

    public Collection<PSObject> GetExecutorState(string? stateRoot = null)
    {
        var parameters = new Dictionary<string, object?>();
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        return Invoke("Get-ParsecExecutorState", parameters);
    }

    public Collection<PSObject> RepairExecutorState(string? stateRoot = null)
    {
        var parameters = new Dictionary<string, object?>();
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        return Invoke("Repair-ParsecExecutorState", parameters);
    }

    public Collection<PSObject> GetDisplays(string? stateRoot = null)
    {
        var parameters = new Dictionary<string, object?>();
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        return Invoke("Get-ParsecDisplay", parameters);
    }

    public Collection<PSObject> GetIngredients(string? name = null)
    {
        var parameters = new Dictionary<string, object?>
        {
            ["Name"] = name ?? "*"
        };
        return Invoke("Get-ParsecIngredient", parameters);
    }

    public Collection<PSObject> InvokeIngredient(
        string name,
        string operation = "apply",
        Dictionary<string, object?>? arguments = null,
        string? tokenId = null,
        string? stateRoot = null)
    {
        var parameters = new Dictionary<string, object?>
        {
            ["Name"] = name,
            ["Operation"] = operation
        };
        if (arguments is not null) parameters["Arguments"] = arguments;
        if (tokenId is not null) parameters["TokenId"] = tokenId;
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        return Invoke("Invoke-ParsecIngredient", parameters);
    }

    public Collection<PSObject> SaveSnapshot(string name, string? stateRoot = null)
    {
        var parameters = new Dictionary<string, object?>
        {
            ["Name"] = name
        };
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        return Invoke("Save-ParsecSnapshot", parameters);
    }

    public Collection<PSObject> TestSnapshot(string name, string? stateRoot = null)
    {
        var parameters = new Dictionary<string, object?>
        {
            ["Name"] = name
        };
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        return Invoke("Test-ParsecSnapshot", parameters);
    }

    private void DrainStreams(System.Management.Automation.PowerShell ps)
    {
        foreach (var info in ps.Streams.Information)
            _logger?.LogInformation("{Message}", info.MessageData?.ToString());

        foreach (var warning in ps.Streams.Warning)
            _logger?.LogWarning("{Message}", warning.Message);

        foreach (var verbose in ps.Streams.Verbose)
            _logger?.LogDebug("{Message}", verbose.Message);

        ps.Streams.ClearStreams();
    }

    private static void ThrowOnErrors(System.Management.Automation.PowerShell ps, string context)
    {
        if (!ps.HadErrors || ps.Streams.Error.Count == 0)
            return;

        var firstError = ps.Streams.Error[0];
        throw new InvalidOperationException(
            $"{context}: {firstError.Exception?.Message ?? firstError.ToString()}",
            firstError.Exception);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _runspace.Close();
        _runspace.Dispose();
    }
}
