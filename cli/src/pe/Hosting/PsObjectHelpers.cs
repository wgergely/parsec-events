using System.Collections;
using System.Collections.Specialized;
using System.Management.Automation;
using System.Text.Json;

namespace ParsecEventExecutor.Cli.Hosting;

/// <summary>
/// Shared utilities for converting PSObject results to .NET types.
/// </summary>
public static class PsObjectHelpers
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true
    };

    /// <summary>
    /// Unwraps a PSObject to an IDictionary if the base object is a dictionary,
    /// otherwise iterates PSObject properties.
    /// </summary>
    public static IDictionary UnwrapToDictionary(object psObject)
    {
        var baseObj = psObject is PSObject pso ? pso.BaseObject : psObject;

        if (baseObj is IDictionary dict)
            return dict;

        var result = new OrderedDictionary();
        if (psObject is PSObject ps)
        {
            foreach (var prop in ps.Properties)
            {
                try { result[prop.Name] = prop.Value; }
                catch { result[prop.Name] = null; }
            }
        }
        return result;
    }

    public static Dictionary<string, object?> ToDictionary(object psObject)
    {
        var dict = new Dictionary<string, object?>();
        var source = UnwrapToDictionary(psObject);
        foreach (DictionaryEntry entry in source)
        {
            dict[entry.Key?.ToString() ?? ""] = entry.Value?.ToString();
        }
        return dict;
    }
}
