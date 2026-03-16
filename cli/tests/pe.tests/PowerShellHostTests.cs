using ParsecEventExecutor.Cli.Hosting;
using Xunit;

namespace ParsecEventExecutor.Cli.Tests;

public class PowerShellHostTests
{
    [Fact]
    public void ModuleLocator_FindsModuleInDevLayout()
    {
        // This test validates that the module locator can find the PS module
        // from the test project's bin directory (development layout)
        var path = ModuleLocator.GetModulePath();

        Assert.NotNull(path);
        Assert.True(Directory.Exists(path), $"Module directory not found: {path}");
        Assert.True(
            File.Exists(Path.Combine(path, "ParsecEventExecutor.psd1")),
            $"Module manifest not found in: {path}");
    }

    [Fact]
    public void PowerShellHost_ImportsModuleSuccessfully()
    {
        using var host = new PowerShellHost();

        // If we get here without exception, the module loaded
        Assert.NotNull(host);
    }

    [Fact]
    public void PowerShellHost_GetIngredients_ReturnsResults()
    {
        using var host = new PowerShellHost();
        var results = host.GetIngredients();

        Assert.NotEmpty(results);
    }

    [Fact]
    public void PowerShellHost_GetRecipes_ReturnsCollection()
    {
        using var host = new PowerShellHost();
        var results = host.GetRecipes();

        // recipes/ directory may be empty — just verify the call succeeds
        Assert.NotNull(results);
    }

    [Fact]
    public void PowerShellHost_GetExecutorState_ReturnsState()
    {
        using var host = new PowerShellHost();

        // Use a temp state root to avoid touching production state
        var tempRoot = Path.Combine(Path.GetTempPath(), $"pe-test-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(tempRoot);
            var results = host.GetExecutorState(tempRoot);

            Assert.NotEmpty(results);
        }
        finally
        {
            if (Directory.Exists(tempRoot))
                Directory.Delete(tempRoot, true);
        }
    }
}
