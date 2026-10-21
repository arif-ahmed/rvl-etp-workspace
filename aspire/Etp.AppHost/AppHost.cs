// Local-dev orchestration for the ETP backend. Lives OUTSIDE rvl-gobcb-backend on purpose:
// services are launched by csproj path and configured purely through env vars that map onto
// the config keys they already read (ConnectionStrings:*, Services:*, Cache:Redis:*, ...).
// Everything else (AWS, Cognito, DgePay...) keeps coming from each service's own user secrets.

var builder = DistributedApplication.CreateBuilder(args);

var servicesRoot = Path.GetFullPath(Path.Combine(builder.AppHostDirectory, "..", "..", "rvl-gobcb-backend", "Services"));

// ---- Infrastructure -------------------------------------------------------------------------
// Fixed local-only password: a data volume keeps the password it was first created with, so a
// random per-run password makes the DB (and every service waiting on it) fail auth after a reset.
var pgPassword = builder.AddParameter("postgres-password", "etp-local-pg", secret: true);
var postgres = builder.AddPostgres("postgres", password: pgPassword)
    .WithDataVolume("etp-postgres-data")
    .WithPgAdmin();
var etpDb = postgres.AddDatabase("etp");          // one DB, each bounded context uses its own schema

// No password: ETP.Core CacheConfig only forwards "host:port" (drops ",password=...") to the DataProtection multiplexer.
var redis = builder.AddRedis("redis")
    .WithPassword(null)
    .WithoutHttpsCertificate()
    .WithDataVolume("etp-redis-data")
    .WithRedisInsight();

// Ticketing hard-codes DynamoDB Local at http://localhost:8000
builder.AddContainer("dynamodb-local", "amazon/dynamodb-local")
    .WithHttpEndpoint(port: 8000, targetPort: 8000, isProxied: false)
    .WithArgs("-jar", "DynamoDBLocal.jar", "-inMemory", "-sharedDb");

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

foreach (var (name, folder, port) in defs)
{
    var csproj = Path.Combine(servicesRoot, folder, $"ETP.{folder}.Service", $"ETP.{folder}.Service.csproj");

    var svc = builder.AddProject(name.ToLowerInvariant(), csproj, launchProfileName: null)
        .WithHttpEndpoint(port: port, isProxied: false)
        .WithHttpHealthCheck("/health")
        .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development")
        .WaitFor(etpDb)
        .WaitFor(redis);

    // ConnectionStrings:<Key> -> Npgsql connection string of the shared DB
    foreach (var key in dbKeys)
        svc.WithEnvironment($"ConnectionStrings__{key}", etpDb.Resource.ConnectionStringExpression);

    // Services:<Key> -> sibling base URLs (plain strings: avoids Aspire circular-reference checks)
    foreach (var (other, _, otherPort) in defs)
        svc.WithEnvironment("Services__" + other, "http://localhost:" + otherPort);

    // Redis (cache + distributed lock)
    svc.WithEnvironment("Cache__Redis__ConnectionString", redis.Resource.ConnectionStringExpression)
       .WithEnvironment("Cache__Redis__InstanceName", "etp-local:")
       .WithEnvironment("Cache__Redis__DefaultDatabase", "0")
       .WithEnvironment("DistributedLock__Redis__EndPoint", redis.Resource.PrimaryEndpoint.Property(EndpointProperty.Host))
       .WithEnvironment("DistributedLock__Redis__Port", redis.Resource.PrimaryEndpoint.Property(EndpointProperty.Port))
       .WithEnvironment("DistributedLock__Redis__AccessKey", "")
       .WithEnvironment("AWS_ENDPOINT_URL", "http://localhost:4566");   // Floci: SQS/SES/Cognito via the local emulator
}

builder.Build().Run();
