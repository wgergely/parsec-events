using System.CommandLine;
using ParsecEventExecutor.Cli.Commands;
using Xunit;

namespace ParsecEventExecutor.Cli.Tests;

public class CommandParsingTests
{
    private static RootCommand CreateRoot()
    {
        var root = new RootCommand("test");
        root.Subcommands.Add(StatusCommand.Create());
        root.Subcommands.Add(ProfileCommand.Create());
        root.Subcommands.Add(RecipeCommand.Create());
        root.Subcommands.Add(RunCommand.Create());
        root.Subcommands.Add(RestoreCommand.Create());
        root.Subcommands.Add(ServiceCommand.Create());
        return root;
    }

    [Fact]
    public void RootCommand_HasExpectedSubcommands()
    {
        var root = CreateRoot();
        var names = root.Subcommands.Select(c => c.Name).ToList();

        Assert.Contains("status", names);
        Assert.Contains("profile", names);
        Assert.Contains("recipe", names);
        Assert.Contains("run", names);
        Assert.Contains("restore", names);
        Assert.Contains("service", names);
    }

    [Fact]
    public void RecipeCommand_HasListAndPreviewSubcommands()
    {
        var recipe = RecipeCommand.Create();
        var names = recipe.Subcommands.Select(c => c.Name).ToList();

        Assert.Contains("list", names);
        Assert.Contains("preview", names);
        Assert.Contains("capture", names);
    }

    [Fact]
    public void ProfileCommand_HasExpectedSubcommands()
    {
        var profile = ProfileCommand.Create();
        var names = profile.Subcommands.Select(c => c.Name).ToList();

        Assert.Contains("set-default", names);
        Assert.Contains("show", names);
    }

    [Fact]
    public void ServiceCommand_HasExpectedSubcommands()
    {
        var service = ServiceCommand.Create();
        var names = service.Subcommands.Select(c => c.Name).ToList();

        Assert.Contains("install", names);
        Assert.Contains("uninstall", names);
        Assert.Contains("start", names);
        Assert.Contains("stop", names);
        Assert.Contains("status", names);
        Assert.Contains("run", names);
    }

    [Fact]
    public void RunCommand_HasNameArgument()
    {
        var run = RunCommand.Create();
        Assert.Single(run.Arguments);
        Assert.Equal("name", run.Arguments[0].Name);
    }

    [Fact]
    public void RunCommand_HasDryRunOption()
    {
        var run = RunCommand.Create();
        var options = run.Options.Select(o => o.Name).ToList();
        Assert.Contains("--dry-run", options);
    }

    [Fact]
    public void RestoreCommand_HasIdOption()
    {
        var restore = RestoreCommand.Create();
        var options = restore.Options.Select(o => o.Name).ToList();
        Assert.Contains("--id", options);
    }

    [Fact]
    public void RestoreCommand_HasListSubcommand()
    {
        var restore = RestoreCommand.Create();
        var names = restore.Subcommands.Select(c => c.Name).ToList();
        Assert.Contains("list", names);
    }
}
