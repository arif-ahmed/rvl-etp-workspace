// Local-dev orchestration for the ETP backend. Lives OUTSIDE rvl-gobcb-backend on purpose:
// services are launched by csproj path and configured purely through env vars that map onto
// the config keys they already read (ConnectionStrings:*, Services:*, Cache:Redis:*, ...).
// Everything else (AWS, Cognito, DgePay...) keeps coming from each service's own user secrets.
//
// This AppHost also owns the infrastructure (PostgreSQL, Redis, DynamoDB Local, Floci = fake AWS, TLS proxy,
// Floci console), so `dotnet run --project aspire/Etp.AppHost` is the only command to start.
// Floci seeding is NOT part of the AppHost: Floci is persistent and the seeds are idempotent, so it is a one-time
// setup step (pwsh ./scripts/Seed-EtpFloci.ps1 then ./scripts/Seed-EtpCognitoUsers.ps1, see docs/local-dev.md).
//
// Start order: infrastructure -> Admin (applies the shared DB migrations before it listens) -> the other services.

using System.Net.Sockets;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;

var builder = DistributedApplication.CreateBuilder(args);

var workspaceRoot = Path.GetFullPath(Path.Combine(builder.AppHostDirectory, "..", ".."));
var servicesRoot = Path.Combine(workspaceRoot, "rvl-gobcb-backend", "Services");

// ---- Infrastructure -------------------------------------------------------------------------
// Fixed host ports, fixed container names and persistent containers/volumes: the user secrets, the seed scripts
// (`docker exec etp-postgres ...`) and the docs all rely on these exact values.
//   PostgreSQL  localhost:5432  db etp_local  user etp  password etp_local_pw
//   Redis       localhost:6379  (no password, no TLS: ETP.Core CacheConfig only forwards host:port)
//   DynamoDB    localhost:8000  (Ticketing hard-codes it; in-memory)
//   Floci       http://localhost:4566 (AWS API), https://localhost:4567 (TLS proxy), http://localhost:4500 (console)
const string pgUser = "etp";
const string pgPassword = "etp_local_pw";
const string pgDatabase = "etp_local";
const string dbConnection = $"Host=localhost;Port=5432;Database={pgDatabase};Username={pgUser};Password={pgPassword};Include Error Detail=true";
const string redisHost = "localhost";
const string redisPort = "6379";

void AddCheck(string name, Func<Task<bool>> probe) =>
    builder.Services.AddHealthChecks().AddAsyncCheck(name, async () =>
        await probe() ? HealthCheckResult.Healthy() : HealthCheckResult.Unhealthy());

// TCP connect on 127.0.0.1 (Docker publishes on IPv4 loopback only; "localhost" tries ::1 first and stalls);
// if `send` is given, also require the reply to start with `expect`.
static async Task<bool> Probe(int port, string? send = null, string? expect = null)
{
    try
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        using var client = new TcpClient();
        await client.ConnectAsync("127.0.0.1", port, cts.Token);
        if (send is null) return true;
        var stream = client.GetStream();
        await stream.WriteAsync(Encoding.ASCII.GetBytes(send), cts.Token);
        var buf = new byte[16];
        var n = await stream.ReadAsync(buf, cts.Token);
        return Encoding.ASCII.GetString(buf, 0, n).StartsWith(expect!, StringComparison.Ordinal);
    }
    catch { return false; }
}

// Volume names are the ones the root docker-compose.yml creates (project "etp-local"), so data carries over when switching between the two.
var postgres = builder.AddPostgres("postgres",
        builder.AddParameter("pg-user", pgUser),
        builder.AddParameter("pg-password", pgPassword, secret: true),
        port: 5432)
    .WithImageTag("16")
    .WithContainerName("etp-postgres")
    .WithDataVolume("etp-local_etp-pgdata")
    .WithEndpointProxySupport(false)
    .WithLifetime(ContainerLifetime.Persistent);
postgres.AddDatabase("etp-db", pgDatabase);

// Plain container instead of AddRedis(): AddRedis() always sets a generated password.
AddCheck("redis-ping", () => Probe(6379, "PING\r\n", "+PONG"));
var redis = builder.AddContainer("redis", "redis", "7")
    .WithContainerName("etp-redis")
    .WithEndpoint(port: 6379, targetPort: 6379, name: "tcp", isProxied: false)
    .WithVolume("etp-local_etp-redis-data", "/data")
    .WithLifetime(ContainerLifetime.Persistent)
    .WithHealthCheck("redis-ping");

AddCheck("dynamodb-port", () => Probe(8000));
var dynamodb = builder.AddContainer("dynamodb", "amazon/dynamodb-local")
    .WithContainerName("etp-dynamodb")
    .WithArgs("-jar", "DynamoDBLocal.jar", "-inMemory", "-sharedDb")
    .WithEndpoint(port: 8000, targetPort: 8000, name: "tcp", isProxied: false)
    .WithHealthCheck("dynamodb-port");

// Floci: local stand-in for AWS (S3, SQS, SES, Cognito). Not real AWS.
// Default storage is in-memory (every restart wipes buckets, queues, Cognito pools), so persist it.
// No Docker socket on purpose: ETP only uses S3/SQS/SES/Cognito.
var floci = builder.AddContainer("floci", "floci/floci", "2.3.0")
    .WithContainerName("etp-floci")
    .WithHttpEndpoint(port: 4566, targetPort: 4566, name: "http", isProxied: false)
    .WithHttpHealthCheck("/health", endpointName: "http")
    .WithEnvironment("FLOCI_STORAGE_MODE", "persistent")
    .WithEnvironment("FLOCI_BASE_URL", "https://localhost:4567")   // OIDC issuer, JWKS and SQS URLs are built from this; HTTPS is served by floci-tls
    .WithVolume("etp-floci-data", "/app/data")
    .WithLifetime(ContainerLifetime.Persistent);

// TLS proxy: the backend's JWT middleware refuses non-HTTPS Cognito metadata. The nginx config is floci/nginx.conf;
// the certificate is machine-specific (scripts/Setup-EtpHttps.ps1, git-ignored).
var certsDir = Path.Combine(workspaceRoot, "certs");
if (!File.Exists(Path.Combine(certsDir, "localhost.pem")) || !File.Exists(Path.Combine(certsDir, "localhost.key")))
    throw new InvalidOperationException($"HTTPS certificate missing in {certsDir}. Run once: pwsh ./scripts/Setup-EtpHttps.ps1");

var flociTls = builder.AddContainer("floci-tls", "nginx", "alpine")
    .WithContainerName("etp-floci-tls")
    .WithBindMount(Path.Combine(workspaceRoot, "floci", "nginx.conf"), "/etc/nginx/conf.d/default.conf", isReadOnly: true)
    .WithBindMount(certsDir, "/certs", isReadOnly: true)
    .WithHttpEndpoint(port: 4569, targetPort: 4569, name: "stub", isProxied: false)   // notification gateway stub, always 200
    .WithEndpoint(port: 4567, targetPort: 4567, name: "tls", isProxied: false)
    .WithHttpHealthCheck("/", endpointName: "stub")
    .WithParentRelationship(floci)   // dashboard grouping only
    .WaitFor(floci);

builder.AddContainer("floci-ui", "floci/floci-ui", "0.7.0")
    .WithContainerName("etp-floci-ui")
    .WithHttpEndpoint(port: 4500, targetPort: 4500, name: "http", isProxied: false)
    .WithEnvironment("FLOCI_ENDPOINT", "http://floci:4566")   // container network name, not localhost
    .WithEnvironment("AWS_REGION", "us-east-1")
    .WithEnvironment("AWS_ACCESS_KEY_ID", "test")
    .WithEnvironment("AWS_SECRET_ACCESS_KEY", "test")          // do NOT set PORT: it moves the server off 4500
    .WithParentRelationship(floci)   // dashboard grouping only
    .WaitFor(floci);

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

// ETP_INFRA_ONLY=true -> only the infrastructure, no build and no services. First-time setup: start this, seed Floci
// by hand, then run scripts/Set-EtpSecrets.ps1 (it reads the Cognito IDs from the seeded Floci).
var infraOnly = string.Equals(builder.Configuration["ETP_INFRA_ONLY"], "true", StringComparison.OrdinalIgnoreCase);
if (infraOnly) skip = defs.Select(d => d.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);

// ---- Build once, then run with --no-build ---------------------------------------------------
// AddProject() starts each service with a plain `dotnet run`, which builds first. Eleven parallel builds
// all rewrite the shared ETP.Core*/obj/**/*.sourcelink.json (even when nothing changed), so a few of them
// fail with "Error writing to source link file ... being used by another process" and a different set of
// services dies on every start. So: one serial build of the solution here, then each service is started
// with `dotnet run --no-build`. Set ETP_NO_BUILD=true to skip the build (e.g. you just built in the IDE).
if (!infraOnly && !string.Equals(builder.Configuration["ETP_NO_BUILD"], "true", StringComparison.OrdinalIgnoreCase))
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

// Admin is the migration leader. About eight services call Database.Migrate() at startup against the same database and
// the same etp.__EFMigrationsHistory table; the backend runs EF Core 8, which has no migration lock, so concurrent first
// runs collide (42P07 "already exists" / "relation does not exist"). Admin migrates before Kestrel listens, so its
// /health only turns green once the schema exists. Every other service waits for it.
// If Admin is in ETP_SKIP (run from the IDE) we gate on its port instead; infra-only has no services to gate.
IResourceBuilder<IResource>? migrationLeader = null;
if (!infraOnly && skip.Contains("Admin"))
{
    var adminPort = defs.First(d => d.Name == "Admin").Port;
    migrationLeader = builder.AddExternalService("admin-ide", $"http://localhost:{adminPort}")
        .WithHttpHealthCheck("/health");
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
        .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development")
        .WaitFor(postgres).WaitFor(redis).WaitFor(dynamodb).WaitFor(flociTls);

    if (name == "Admin") migrationLeader = svc;
    else if (migrationLeader is not null) svc.WaitFor(migrationLeader);

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
