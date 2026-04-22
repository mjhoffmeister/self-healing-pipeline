using Xunit;

namespace SelfHealingDemo.Api.Tests;

public class GreetingServiceTests
{
    [Theory]
    [InlineData(null, "Hello, world!")]
    [InlineData("", "Hello, world!")]
    [InlineData("   ", "Hello, world!")]
    [InlineData("Ada", "Hello, Ada!")]
    [InlineData("  Grace  ", "Hello, Grace!")]
    public void Greet_returns_expected_string(string? input, string expected)
    {
        Assert.Equal(expected, GreetingService.Greet(input));
    }

    [Theory]
    [InlineData(0, 0, 0)]
    [InlineData(2, 3, 5)]
    [InlineData(-4, 4, 0)]
    public void Add_returns_sum(int a, int b, int expected)
    {
        Assert.Equal(expected, GreetingService.Add(a, b));
    }
}
