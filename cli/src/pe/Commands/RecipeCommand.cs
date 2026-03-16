using System.Collections;
using System.CommandLine;
using System.Text.Json;
using ParsecEventExecutor.Cli.Hosting;

namespace ParsecEventExecutor.Cli.Commands;

public static class RecipeCommand
{

    public static Command Create()
    {
        var command = new Command("recipe", "Manage recipes");
        command.Subcommands.Add(CreateListCommand());
        command.Subcommands.Add(CreatePreviewCommand());
        command.Subcommands.Add(CreateCaptureCommand());
        return command;
    }

    private static Command CreateListCommand()
    {
        var jsonOption = new Option<bool>("--json") { Description = "Output raw JSON" };

        var command = new Command("list", "List all available recipes");
        command.Options.Add(jsonOption);

        command.SetAction(parseResult =>
        {
            var json = parseResult.GetValue(jsonOption);
            HandleList(json);
        });

        return command;
    }

    private static void HandleList(bool json)
    {
        using var host = new PowerShellHost();
        var results = host.GetRecipes();

        if (json)
        {
            var list = results.Select(PsObjectHelpers.ToDictionary).ToList();
            Console.WriteLine(JsonSerializer.Serialize(list, PsObjectHelpers.JsonOptions));
            return;
        }

        if (results.Count == 0)
        {
            Console.WriteLine("No recipes found.");
            return;
        }

        Console.WriteLine($"{"Name",-30} {"Event",-12} {"Username",-20} {"Steps",-6} Description");
        Console.WriteLine(new string('-', 90));

        foreach (var recipe in results)
        {
            var name = recipe.Properties["name"]?.Value?.ToString() ?? "";
            var desc = recipe.Properties["description"]?.Value?.ToString() ?? "";
            var eventType = recipe.Properties["event_type"]?.Value?.ToString() ?? "";
            var username = recipe.Properties["username"]?.Value?.ToString() ?? "";
            var steps = recipe.Properties["steps"]?.Value;
            var stepCount = steps is System.Collections.ICollection col ? col.Count.ToString() : "?";

            Console.WriteLine($"  {name,-28} {eventType,-12} {username,-20} {stepCount,-6} {desc}");
        }
    }

    private static Command CreatePreviewCommand()
    {
        var nameArg = new Argument<string>("name") { Description = "Recipe name to preview" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("preview", "Show what a recipe would do without executing");
        command.Arguments.Add(nameArg);
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var name = parseResult.GetValue(nameArg);
            var stateRoot = parseResult.GetValue(stateRootOption);
            HandlePreview(name!, stateRoot);
        });

        return command;
    }

    private static void HandlePreview(string name, string? stateRoot)
    {
        using var host = new PowerShellHost();
        var results = host.InvokeRecipe(name, stateRoot, whatIf: true);

        Console.WriteLine($"Preview: {name}");
        Console.WriteLine(new string('-', 40));

        foreach (var result in results)
        {
            Console.WriteLine(result);
        }

        if (results.Count == 0)
        {
            Console.WriteLine("  (no output from dry run)");
        }
    }

    private static Command CreateCaptureCommand()
    {
        var nameArg = new Argument<string>("name") { Description = "Name for the new recipe" };
        var eventTypeOption = new Option<string>("--event-type") { Description = "Event type (connect or disconnect)", DefaultValueFactory = _ => "connect" };
        var usernameOption = new Option<string?>("--username") { Description = "Parsec username filter (e.g., Phone#1234)" };
        var descriptionOption = new Option<string?>("--description") { Description = "Recipe description" };
        var stateRootOption = new Option<string?>("--state-root") { Description = "Override state root directory" };

        var command = new Command("capture", "Capture current system state as a new recipe");
        command.Arguments.Add(nameArg);
        command.Options.Add(eventTypeOption);
        command.Options.Add(usernameOption);
        command.Options.Add(descriptionOption);
        command.Options.Add(stateRootOption);

        command.SetAction(parseResult =>
        {
            var name = parseResult.GetValue(nameArg)!;
            var eventType = parseResult.GetValue(eventTypeOption)!;
            var username = parseResult.GetValue(usernameOption);
            var description = parseResult.GetValue(descriptionOption);
            var stateRoot = parseResult.GetValue(stateRootOption);
            HandleCapture(name, eventType, username, description, stateRoot);
        });

        return command;
    }

    private static void HandleCapture(string name, string eventType, string? username, string? description, string? stateRoot)
    {
        using var host = new PowerShellHost();

        Console.WriteLine($"Capturing current system state as recipe '{name}'...");

        var parameters = new Dictionary<string, object?>
        {
            ["Name"] = name,
            ["EventType"] = eventType
        };
        if (username is not null) parameters["Username"] = username;
        if (description is not null) parameters["Description"] = description;
        if (stateRoot is not null) parameters["StateRoot"] = stateRoot;

        var results = host.Invoke("New-ParsecRecipeFromCapture", parameters);

        if (results.Count > 0)
        {
            var result = PsObjectHelpers.UnwrapToDictionary(results[0]);
            Console.WriteLine($"Recipe created: {result["path"]}");
            Console.WriteLine($"  Name:       {result["name"]}");
            Console.WriteLine($"  Event type: {result["event_type"]}");
            Console.WriteLine($"  Steps:      {result["steps"]}");
        }
    }
}
