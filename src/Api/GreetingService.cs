namespace SelfHealingDemo.Api;

/// <summary>
/// Pure logic kept separate from Program.cs so unit tests don't need a WebApplicationFactory.
/// </summary>
public static class GreetingService
{
    public static string Greet(string? name)
    {
        var trimmed = string.IsNullOrWhiteSpace(name) ? "world" : name.Trim();
        return $"Helo, {trimmed}!";
    }

    public static string GreetFormal(string? name)
    {
        var trimmed = string.IsNullOrWhiteSpace(name) ? "world" : name.Trim();
        return $"Good day, {trimmed}.";
    }

    public static int Add(int a, int b) => a + b;
}
