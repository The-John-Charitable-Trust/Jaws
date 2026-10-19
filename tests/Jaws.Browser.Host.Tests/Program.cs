using System.Text;
using Jaws.Browser.Host;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;

var failures = new List<string>();
void Check(string name, Action test)
{
    try
    {
        test();
        Console.WriteLine($"PASS: {name}");
    }
    catch (Exception ex)
    {
        failures.Add($"FAIL: {name} - {ex.Message}");
        Console.WriteLine(failures[^1]);
    }
}

Check("audience-only token cannot fill a credential", AudienceOnlyCannotFill);
Check("a locally signed token can fill a credential", SignedTokenCanFill);
Check("a bad signature is refused", BadSignatureIsRefused);
Check("the wrong audience is refused", WrongAudienceIsRefused);
Check("signature parameters stay unset until a tenant id exists", TenantIdGatesSignatureParameters);

if (failures.Count > 0)
{
    Environment.Exit(1);
}

static void AudienceOnlyCannotFill()
{
    var jwt = WriteToken(audience: "api://jaws-browser", key: Key("0123456789abcdef0123456789abcdef"));
    var auth = BrowserToken.Authorize("Bearer " + jwt, "api://jaws-browser", signature: null);
    if (!auth.AudienceAccepted || auth.SignatureValid || auth.CanFillCredential)
    {
        throw new InvalidOperationException("Audience-only acceptance must not fill a vault credential.");
    }
}

static void SignedTokenCanFill()
{
    var key = Key("0123456789abcdef0123456789abcdef");
    var jwt = WriteToken(audience: "api://jaws-browser", key);
    var auth = BrowserToken.Authorize("Bearer " + jwt, "api://jaws-browser", Signature(key));
    if (!auth.AudienceAccepted || !auth.SignatureValid || !auth.CanFillCredential)
    {
        throw new InvalidOperationException("A token signed with the expected key must be allowed to fill a credential.");
    }
}

static void BadSignatureIsRefused()
{
    var jwt = WriteToken(audience: "api://jaws-browser", Key("0123456789abcdef0123456789abcdef"));
    var auth = BrowserToken.Authorize("Bearer " + jwt, "api://jaws-browser", Signature(Key("abcdef0123456789abcdef0123456789")));
    if (auth.AudienceAccepted || auth.SignatureValid || auth.CanFillCredential)
    {
        throw new InvalidOperationException("A token with the wrong signature must be refused.");
    }
}

static void WrongAudienceIsRefused()
{
    var key = Key("0123456789abcdef0123456789abcdef");
    var jwt = WriteToken(audience: "api://other", key);
    var auth = BrowserToken.Authorize("Bearer " + jwt, "api://jaws-browser", Signature(key));
    if (auth.AudienceAccepted || auth.CanFillCredential)
    {
        throw new InvalidOperationException("The wrong audience must be refused before a credential fill.");
    }
}

static void TenantIdGatesSignatureParameters()
{
    if (BrowserToken.CreateSignatureParameters("  ", "api://jaws-browser") is not null)
    {
        throw new InvalidOperationException("A blank tenant id must leave signature validation unset.");
    }
    var parameters = BrowserToken.CreateSignatureParameters("33333333-3333-3333-3333-333333333333", "api://jaws-browser");
    if (parameters is null || parameters.ValidAudience != "api://jaws-browser" || parameters.ConfigurationManager is null)
    {
        throw new InvalidOperationException("A tenant id must select signature validation without contacting the tenant.");
    }
}

static SymmetricSecurityKey Key(string text) => new(Encoding.UTF8.GetBytes(text));

static TokenValidationParameters Signature(SymmetricSecurityKey key) => new()
{
    ValidateIssuer = false,
    ValidateAudience = true,
    ValidAudience = "api://jaws-browser",
    ValidateLifetime = true,
    ValidateIssuerSigningKey = true,
    IssuerSigningKey = key
};

static string WriteToken(string audience, SymmetricSecurityKey key)
{
    var token = new JwtSecurityToken(
        issuer: "https://login.microsoftonline.com/local/v2.0",
        audience: audience,
        expires: DateTime.UtcNow.AddMinutes(5),
        signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
    return new JwtSecurityTokenHandler().WriteToken(token);
}
