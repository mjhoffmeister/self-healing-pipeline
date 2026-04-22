using SelfHealingDemo.Api;

var builder = WebApplication.CreateSlimBuilder(args);

var app = builder.Build();

app.MapGet("/", () => "self-healing-demo api");
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));
app.MapGet("/greet/{name?}", (string? name) => GreetingService.Greet(name));
app.MapGet("/add", (int a, int b) => GreetingService.Add(a, b));

app.Run();

// Exposed so WebApplicationFactory<Program> works in integration tests if added later.
public partial class Program;
