using System.Collections.Concurrent;
using System.Diagnostics;
using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using Jaws.Browser.Host;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Playwright;

var audience = Environment.GetEnvironmentVariable("JAWS_BROWSER_AUDIENCE");
if (string.IsNullOrWhiteSpace(audience))
{
    audience = "api://jaws-browser";
}
var timeoutMinutes = ReadInt("JAWS_BROWSER_TIMEOUT_MINUTES", 10);
var stepLimit = ReadInt("JAWS_BROWSER_STEP_LIMIT", 50);
var maxSessions = ReadInt("JAWS_BROWSER_MAX_SESSIONS", 3);
var allowListPath = Environment.GetEnvironmentVariable("JAWS_BROWSER_ALLOW_LIST_PATH");
var allowListSecret = Environment.GetEnvironmentVariable("JAWS_BROWSER_ALLOW_LIST_SECRET_URI");
var credentialSecret = Environment.GetEnvironmentVariable("JAWS_BROWSER_CREDENTIAL_SECRET_URI");
var screenshotRoot = Environment.GetEnvironmentVariable("JAWS_BROWSER_SCREENSHOT_DIR");
if (string.IsNullOrWhiteSpace(screenshotRoot))
{
    screenshotRoot = Path.Combine(Path.GetTempPath(), "jaws-browser-shots");
}
Directory.CreateDirectory(screenshotRoot);
var evidenceRoot = Environment.GetEnvironmentVariable("JAWS_BROWSER_EVIDENCE_DIR");
if (string.IsNullOrWhiteSpace(evidenceRoot))
{
    evidenceRoot = Path.Combine(Path.GetTempPath(), "jaws-browser-evidence");
}
Directory.CreateDirectory(evidenceRoot);

var sessions = new ConcurrentDictionary<string, BrowserSession>(StringComparer.Ordinal);
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/healthz", () => Results.Ok(new { status = "ready", component = "jaws-browser-host" }));

app.MapPost("/sessions", async (HttpRequest request) =>
{
    if (!Authorize(request, audience))
    {
        return Unauthorized();
    }
    var active = sessions.Values.Count(item => !item.Closed);
    if (active >= maxSessions)
    {
        return Problem("browser_queue_timeout", "The session limit is full. Wait and retry.", 429);
    }
    var id = Guid.NewGuid().ToString("N");
    var session = await BrowserSession.OpenAsync(id, screenshotRoot);
    sessions[id] = session;
    WriteEvidence(evidenceRoot, id, "session_open", id, "opened", 0, null);
    return Results.Ok(new { sessionId = id, stepLimit, timeoutMinutes });
});

app.MapPost("/sessions/{id}/navigate", async (string id, ActionBody body, HttpRequest request) =>
{
    if (!Authorize(request, audience))
    {
        return Unauthorized();
    }
    var session = RequireSession(sessions, id);
    if (session is null)
    {
        return Problem("session_not_found", "The browser session is not open.", 404);
    }
    var allow = await ReadAllowListAsync(allowListPath, allowListSecret);
    if (!BrowserPolicy.IsAllowed(body.Url ?? "", allow))
    {
        WriteEvidence(evidenceRoot, id, "browser_navigate", body.Url ?? "", "rejected", 0, null);
        return Problem("allow_list_rejected", "Navigation was rejected because the URL is outside the allow-list.", 403);
    }
    return await RunAsync(session, evidenceRoot, id, "browser_navigate", body.Url ?? "", stepLimit, timeoutMinutes, async () =>
    {
        var finalUrl = await session.NavigateAsync(body.Url!, TimeSpan.FromSeconds(30));
        if (!BrowserPolicy.IsAllowed(finalUrl, allow))
        {
            await session.CloseAsync();
            throw new BrowserCommandException("allow_list_rejected", "The page left the allow-list. The session was closed.");
        }
        var shot = await session.ScreenshotAsync("navigate");
        return new { url = finalUrl, screenshot = shot };
    });
});

app.MapPost("/sessions/{id}/snapshot", async (string id, HttpRequest request) =>
{
    if (!Authorize(request, audience))
    {
        return Unauthorized();
    }
    var session = RequireSession(sessions, id);
    if (session is null)
    {
        return Problem("session_not_found", "The browser session is not open.", 404);
    }
    return await RunAsync(session, evidenceRoot, id, "browser_snapshot", session.Url, stepLimit, timeoutMinutes, async () =>
    {
        var text = await session.SnapshotAsync();
        return new { url = session.Url, snapshot = text };
    });
});

app.MapPost("/sessions/{id}/click", async (string id, SelectorBody body, HttpRequest request) =>
{
    if (!Authorize(request, audience))
    {
        return Unauthorized();
    }
    var session = RequireSession(sessions, id);
    if (session is null)
    {
        return Problem("session_not_found", "The browser session is not open.", 404);
    }
    return await RunAsync(session, evidenceRoot, id, "browser_click", body.Selector ?? "", stepLimit, timeoutMinutes, async () =>
    {
        await session.ClickAsync(body.Selector ?? "");
        return new { url = session.Url, clicked = body.Selector };
    });
});

app.MapPost("/sessions/{id}/type", async (string id, TypeBody body, HttpRequest request) =>
{
    if (!Authorize(request, audience))
    {
        return Unauthorized();
    }
    var session = RequireSession(sessions, id);
    if (session is null)
    {
        return Problem("session_not_found", "The browser session is not open.", 404);
    }
    var selector = body.Selector ?? "";
    if (BrowserPolicy.IsCredentialField(selector))
    {
        var filled = await session.FillCredentialAsync(credentialSecret, selector);
        WriteEvidence(evidenceRoot, id, "browser_type", selector, filled ? "vault_filled" : "credential_not_registered", 0, null);
        return filled
            ? Results.Ok(new { url = session.Url, credential = "filled" })
            : Problem("credential_not_registered", "No vault entry is registered for this site. The agent text was discarded.", 404);
    }
    return await RunAsync(session, evidenceRoot, id, "browser_type", selector, stepLimit, timeoutMinutes, async () =>
    {
        await session.TypeAsync(selector, body.Text ?? "");
        return new { url = session.Url, typed = true };
    });
});

app.MapPost("/sessions/{id}/screenshot", async (string id, HttpRequest request) =>
{
    if (!Authorize(request, audience))
    {
        return Unauthorized();
    }
    var session = RequireSession(sessions, id);
    if (session is null)
    {
        return Problem("session_not_found", "The browser session is not open.", 404);
    }
    return await RunAsync(session, evidenceRoot, id, "browser_screenshot", session.Url, stepLimit, timeoutMinutes, async () =>
    {
        var shot = await session.ScreenshotAsync("manual");
        return new { url = session.Url, screenshot = shot };
    });
});

app.MapPost("/sessions/{id}/close", async (string id, HttpRequest request) =>
{
    if (!Authorize(request, audience))
    {
        return Unauthorized();
    }
    if (!sessions.TryGetValue(id, out var session))
    {
        return Problem("session_not_found", "The browser session is not open.", 404);
    }
    var shot = session.Closed ? null : await session.ScreenshotAsync("close");
    await session.CloseAsync();
    WriteEvidence(evidenceRoot, id, "browser_close", session.Url, "closed", 0, shot);
    return Results.Ok(new { sessionId = id, closed = true, screenshot = shot });
});

app.Run();

static int ReadInt(string name, int fallback)
{
    var text = Environment.GetEnvironmentVariable(name);
    return int.TryParse(text, out var value) && value > 0 ? value : fallback;
}

static bool Authorize(HttpRequest request, string audience)
{
    var header = request.Headers.Authorization.ToString();
    if (!header.StartsWith("Bearer ", StringComparison.Ordinal) || header.Length < 8)
    {
        return false;
    }
    var token = header["Bearer ".Length..].Trim();
    try
    {
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        return jwt.Audiences.Contains(audience, StringComparer.Ordinal);
    }
    catch (ArgumentException)
    {
        return false;
    }
}

static IResult Unauthorized()
{
    return Results.Json(new { error = new { code = "unauthorized", message = "A managed-identity token for the browser service is required." } }, statusCode: 401);
}

static IResult Problem(string code, string message, int status)
{
    return Results.Json(new { error = new { code, message } }, statusCode: status);
}

static BrowserSession? RequireSession(ConcurrentDictionary<string, BrowserSession> sessions, string id)
{
    if (!sessions.TryGetValue(id, out var session) || session.Closed)
    {
        return null;
    }
    return session;
}

static async Task<IResult> RunAsync(
    BrowserSession session,
    string evidenceRoot,
    string id,
    string action,
    string target,
    int stepLimit,
    int timeoutMinutes,
    Func<Task<object>> work)
{
    if (session.Steps >= stepLimit || DateTimeOffset.UtcNow - session.Opened > TimeSpan.FromMinutes(timeoutMinutes))
    {
        var shot = await session.ScreenshotAsync("limit");
        await session.CloseAsync();
        WriteEvidence(evidenceRoot, id, action, target, "timeout", 0, shot);
        return Problem("browser_timeout", "The browser task reached its step limit or timeout. The session was closed.", 408);
    }
    var watch = Stopwatch.StartNew();
    try
    {
        var payload = await work();
        session.Steps++;
        WriteEvidence(evidenceRoot, id, action, target, "ok", watch.ElapsedMilliseconds, null);
        return Results.Ok(payload);
    }
    catch (BrowserCommandException ex)
    {
        var shot = await session.ScreenshotAsync("failure");
        WriteEvidence(evidenceRoot, id, action, target, ex.Code, watch.ElapsedMilliseconds, shot);
        var status = ex.Code == "allow_list_rejected" ? 403 : 503;
        return Problem(ex.Code, ex.Message, status);
    }
    catch (TimeoutException)
    {
        var shot = await session.ScreenshotAsync("unreachable");
        WriteEvidence(evidenceRoot, id, action, target, "browser_unreachable", watch.ElapsedMilliseconds, shot);
        return Problem("browser_unreachable", "The browser service did not finish the action within 30 seconds.", 503);
    }
    catch (PlaywrightException ex)
    {
        var shot = await session.ScreenshotAsync("unreachable");
        WriteEvidence(evidenceRoot, id, action, target, "browser_unreachable", watch.ElapsedMilliseconds, shot);
        return Problem("browser_unreachable", "The browser engine could not complete the action. " + ex.Message, 503);
    }
}

static async Task<IReadOnlyList<string>> ReadAllowListAsync(string? path, string? secretUri)
{
    var json = "";
    if (!string.IsNullOrWhiteSpace(secretUri))
    {
        var client = new SecretClient(new Uri(SecretVaultUri(secretUri)), new DefaultAzureCredential());
        var secret = await client.GetSecretAsync(SecretName(secretUri));
        json = secret.Value.Value;
    }
    else if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
    {
        json = await File.ReadAllTextAsync(path);
    }
    if (string.IsNullOrWhiteSpace(json))
    {
        return Array.Empty<string>();
    }
    var document = JsonSerializer.Deserialize<AllowListFile>(json);
    return document?.Urls ?? Array.Empty<string>();
}

static string SecretVaultUri(string secretUri)
{
    var uri = new Uri(secretUri);
    return $"{uri.Scheme}://{uri.Host}";
}

static string SecretName(string secretUri)
{
    var parts = new Uri(secretUri).AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
    var index = Array.IndexOf(parts, "secrets");
    if (index < 0 || index + 1 >= parts.Length)
    {
        throw new InvalidOperationException("The Key Vault secret URI has no secret name.");
    }
    return parts[index + 1];
}

static void WriteEvidence(string root, string sessionId, string action, string target, string outcome, long durationMs, string? screenshot)
{
    var line = JsonSerializer.Serialize(new
    {
        timestamp = DateTimeOffset.UtcNow.ToString("o"),
        sessionId,
        action,
        target,
        outcome,
        durationMs,
        screenshot
    });
    File.AppendAllText(Path.Combine(root, sessionId + ".jsonl"), line + Environment.NewLine);
}

internal sealed class BrowserCommandException : Exception
{
    public BrowserCommandException(string code, string message) : base(message)
    {
        Code = code;
    }

    public string Code { get; }
}

internal sealed class CredentialEntry
{
    public string? Username { get; set; }
    public string? Password { get; set; }
}

internal sealed class AllowListFile
{
    public string[] Urls { get; set; } = Array.Empty<string>();
}

internal sealed class ActionBody
{
    public string? Url { get; set; }
}

internal sealed class SelectorBody
{
    public string? Selector { get; set; }
}

internal sealed class TypeBody
{
    public string? Selector { get; set; }
    public string? Text { get; set; }
}

internal sealed class BrowserSession : IAsyncDisposable
{
    private static IPlaywright? _playwright;
    private static IBrowser? _browser;
    private readonly string _screenshotRoot;
    private IBrowserContext? _context;
    private IPage? _page;

    private BrowserSession(string id, string screenshotRoot)
    {
        Id = id;
        _screenshotRoot = screenshotRoot;
        Opened = DateTimeOffset.UtcNow;
    }

    public string Id { get; }
    public string Url { get; private set; } = "";
    public int Steps { get; set; }
    public bool Closed { get; private set; }
    public DateTimeOffset Opened { get; }

    public static async Task<BrowserSession> OpenAsync(string id, string screenshotRoot)
    {
        var session = new BrowserSession(id, screenshotRoot);
        _playwright ??= await Playwright.CreateAsync();
        if (_browser is null)
        {
            var options = new BrowserTypeLaunchOptions
            {
                Headless = true,
                Args = ["--disable-dev-shm-usage", "--no-sandbox"]
            };
            var chromium = Environment.GetEnvironmentVariable("JAWS_BROWSER_CHROMIUM_PATH");
            if (!string.IsNullOrWhiteSpace(chromium))
            {
                options.ExecutablePath = chromium;
            }
            _browser = await _playwright.Chromium.LaunchAsync(options);
        }
        session._context = await _browser.NewContextAsync(new BrowserNewContextOptions
        {
            AcceptDownloads = false,
            JavaScriptEnabled = true
        });
        session._page = await session._context.NewPageAsync();
        return session;
    }

    public async Task<string> NavigateAsync(string url, TimeSpan timeout)
    {
        var page = RequirePage();
        var response = await page.GotoAsync(url, new PageGotoOptions { Timeout = (float)timeout.TotalMilliseconds, WaitUntil = WaitUntilState.DOMContentLoaded });
        if (response is null)
        {
            throw new BrowserCommandException("browser_unreachable", "The browser did not receive a response.");
        }
        Url = page.Url;
        return Url;
    }

    public async Task<string> SnapshotAsync()
    {
        var page = RequirePage();
        var text = await page.InnerTextAsync("body");
        return text.Length > 4000 ? text[..4000] : text;
    }

    public async Task ClickAsync(string selector)
    {
        await RequirePage().ClickAsync(selector, new PageClickOptions { Timeout = 30000 });
        Url = RequirePage().Url;
    }

    public async Task TypeAsync(string selector, string text)
    {
        await RequirePage().FillAsync(selector, text, new PageFillOptions { Timeout = 30000 });
    }

    public async Task<bool> FillCredentialAsync(string? secretUri, string selector)
    {
        if (string.IsNullOrWhiteSpace(secretUri))
        {
            return false;
        }
        var client = new SecretClient(new Uri(SecretVault(secretUri)), new DefaultAzureCredential());
        var mapSecret = await client.GetSecretAsync(SecretName(secretUri));
        var map = JsonSerializer.Deserialize<Dictionary<string, CredentialEntry>>(mapSecret.Value.Value) ?? new Dictionary<string, CredentialEntry>(StringComparer.OrdinalIgnoreCase);
        var site = new Uri(string.IsNullOrWhiteSpace(Url) ? "https://invalid.local" : Url).IdnHost;
        if (!map.TryGetValue(site, out var entry) || string.IsNullOrWhiteSpace(entry.Password))
        {
            return false;
        }
        await RequirePage().FillAsync(selector, entry.Password, new PageFillOptions { Timeout = 30000 });
        return true;
    }

    public async Task<string> ScreenshotAsync(string label)
    {
        if (Closed || _page is null)
        {
            return "";
        }
        var directory = Path.Combine(_screenshotRoot, Id);
        Directory.CreateDirectory(directory);
        var name = label + "-" + Guid.NewGuid().ToString("N") + ".png";
        var path = Path.Combine(directory, name);
        await _page.ScreenshotAsync(new PageScreenshotOptions { Path = path, Timeout = 30000 });
        return "evidence://" + Id + "/" + name;
    }

    public async Task CloseAsync()
    {
        if (Closed)
        {
            return;
        }
        Closed = true;
        if (_context is not null)
        {
            await _context.CloseAsync();
        }
    }

    public async ValueTask DisposeAsync()
    {
        await CloseAsync();
    }

    private IPage RequirePage()
    {
        if (Closed || _page is null)
        {
            throw new BrowserCommandException("session_closed", "The browser session is closed.");
        }
        return _page;
    }

    private static string SecretVault(string secretUri)
    {
        var uri = new Uri(secretUri);
        return $"{uri.Scheme}://{uri.Host}";
    }

    private static string SecretName(string secretUri)
    {
        var parts = new Uri(secretUri).AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var index = Array.IndexOf(parts, "secrets");
        if (index < 0 || index + 1 >= parts.Length)
        {
            throw new BrowserCommandException("credential_not_registered", "The credential scope URI is not a Key Vault secret.");
        }
        return parts[index + 1];
    }
}
