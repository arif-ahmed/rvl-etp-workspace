// Local-dev orchestration for the ETP backend. Lives OUTSIDE rvl-gobcb-backend on purpose:
// services are launched by csproj path and configured purely through env vars that map onto
// the config keys they already read (ConnectionStrings:*, Services:*, Cache:Redis:*, ...).
// Everything else (AWS, Cognito, DgePay...) keeps coming from each service's own user secrets.

var builder = DistributedApplication.CreateBuilder(args);

var servicesRoot = Path.GetFullPath(Path.Combine(builder.AppHostDirectory, "..", "..", "rvl-gobcb-backend", "Services"));

// ---- Infrastructure -------------------------------------------------------------------------
// PostgreSQL, Redis, DynamoDB Local and Floci (fake AWS) come from the workspace docker-compose.yml (`docker compose up -d`,
// start it BEFORE the AppHost). Aspire only points the services at them; the values match that compose file
// and scripts/user-secrets.example.json.
const string dbConnection = "Host=localhost;Port=5432;Database=etp_local;Username=etp;Password=etp_local_pw;Include Error Detail=true";
const string redisHost = "localhost";
const string redisPort = "6379";

// ---- Services -------------------------------------------------------------------------------
// name -> (folder, fixed port). Fixed ports because services call each other through Services:* URLs.
// (launchSettings.json ports collide, e.g. Scheduler/Utility both use 5033, so we do not use them.)
var defs = new (string Name, string Folder, int Port)[]
{
    ("Admin",            "Admin",            5101),
    ("Booking",          "Booking",          5102),
    ("Event",            "Event",            5103),
    ("Platform",         "Platform",         5104),
    ("PushNotification", "PushNotification", 5105),
    ("Scheduler",        "Scheduler",        5106),
    ("TicketChecker",    "TicketChecker",    5107),
    ("Ticketing",        "Ticketing",        5108),
    ("UserAuth",         "UserAuth",         5109),
    ("UserIssue",        "UserIssue",        5110),
    ("Utility",          "Utility",          5111),
};

// Config keys under ConnectionStrings:* that the services may read (all point to the same DB by default).
string[] dbKeys = ["Admin", "Booking", "Event", "Platform", "Scheduler", "TicketChecker",
                   "Ticketing", "UserAuth", "UserIssue", "PushNotification"];

// ETP_SKIP=Event,Booking -> Aspire does not launch those services, so you can run them yourself from
// your IDE (same fixed port) and hit breakpoints from the very first line. The others still find them
// through the Services__* URLs below. See docs/local-dev.md.
var skip = (builder.Configuration["ETP_SKIP"] ?? "")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    .ToHashSet(StringComparer.OrdinalIgnoreCase);

// ---- Build once, then run with --no-build ---------------------------------------------------
// AddProject() starts each service with a plain `dotnet run`, which builds first. Eleven parallel builds
// all rewrite the shared ETP.Core*/obj/**/*.sourcelink.json (even when nothing changed), so a few of them
// fail with "Error writing to source link file ... being used by another process" and a different set of
// services dies on every start. So: one serial build of the solution here, then each service is started
// with `dotnet run --no-build`. Set ETP_NO_BUILD=true to skip the build (e.g. you just built in the IDE).
if (!string.Equals(builder.Configuration["ETP_NO_BUILD"], "true", StringComparison.OrdinalIgnoreCase))
{
    var sln = Path.GetFullPath(Path.Combine(servicesRoot, "..", "RVL-ETP.BackEnd.sln"));
    Console.WriteLine($"[Etp.AppHost] Building {sln} once before starting the services ...");
    using var build = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("dotnet", $"build \"{sln}\" --nologo -v q")
    {
        UseShellExecute = false,
    })!;
    build.WaitForExit();
    if (build.ExitCode != 0)
        throw new InvalidOperationException($"dotnet build {sln} failed (exit {build.ExitCode}); fix the build errors and start the AppHost again.");
}

foreach (var (name, folder, port) in defs)
{
    if (skip.Contains(name)) continue;

    var csproj = Path.Combine(servicesRoot, folder, $"ETP.{folder}.Service", $"ETP.{folder}.Service.csproj");

    var svc = builder.AddExecutable(name.ToLowerInvariant(), "dotnet", Path.GetDirectoryName(csproj)!,
            "run", "--project", csproj, "--configuration", "Debug", "--no-build", "--no-launch-profile")
        .WithHttpEndpoint(port: port, isProxied: false)
        .WithHttpHealthCheck("/health")
        .WithEnvironment("ASPNETCORE_URLS", "http://localhost:" + port)
        .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development");

    // ConnectionStrings:<Key> -> Npgsql connection string of the shared DB
    foreach (var key in dbKeys)
        svc.WithEnvironment($"ConnectionStrings__{key}", dbConnection);

    // UserIssue has no appsettings.json in the repo, so its Application section is supplied here
    if (name == "UserIssue")
        svc.WithEnvironment("Application__ServiceName", "userissue")
           .WithEnvironment("Application__Title", "RVL ETP ETicketing - User Issue API")
           .WithEnvironment("Application__Description", "API for user issue related utilities");

    // Services:<Key> -> sibling base URLs (plain strings: avoids Aspire circular-reference checks)
    foreach (var (other, _, otherPort) in defs)
        svc.WithEnvironment("Services__" + other, "http://localhost:" + otherPort);

    // Redis (cache + distributed lock)
    svc.WithEnvironment("Cache__Redis__ConnectionString", $"{redisHost}:{redisPort}")
       .WithEnvironment("Cache__Redis__InstanceName", "etp-local:")
       .WithEnvironment("Cache__Redis__DefaultDatabase", "0")
       .WithEnvironment("DistributedLock__Redis__EndPoint", redisHost)
       .WithEnvironment("DistributedLock__Redis__Port", redisPort)
       .WithEnvironment("DistributedLock__Redis__AccessKey", "")
       .WithEnvironment("AWS_ENDPOINT_URL", "http://localhost:4566")   // Floci; its region is us-east-1, which is what the AWS SDK signs with once an endpoint is set
       .WithEnvironment("Notification__Endpoint", "http://localhost:4569/");   // secrets hold a placeholder SMS gateway; floci-tls answers 200 on :4569 so admin user create / password reset work locally
}

builder.Build().Run();
