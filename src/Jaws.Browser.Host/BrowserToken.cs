using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace Jaws.Browser.Host;

public sealed record BrowserAuthorization(bool AudienceAccepted, bool SignatureValid)
{
    public bool CanFillCredential => SignatureValid;
}

public static class BrowserToken
{
    public static TokenValidationParameters? CreateSignatureParameters(string? tenantId, string audience)
    {
        if (string.IsNullOrWhiteSpace(tenantId))
        {
            return null;
        }

        var address = $"https://login.microsoftonline.com/{tenantId}/v2.0/.well-known/openid-configuration";
        var manager = new ConfigurationManager<OpenIdConnectConfiguration>(address, new OpenIdConnectConfigurationRetriever());
        return new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuers =
            [
                $"https://login.microsoftonline.com/{tenantId}/v2.0",
                $"https://sts.windows.net/{tenantId}/"
            ],
            ValidateAudience = true,
            ValidAudience = audience,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ConfigurationManager = manager
        };
    }

    public static BrowserAuthorization Authorize(string? header, string audience, TokenValidationParameters? signature)
    {
        if (string.IsNullOrWhiteSpace(header) || !header.StartsWith("Bearer ", StringComparison.Ordinal) || header.Length < 8)
        {
            return new BrowserAuthorization(false, false);
        }

        var token = header["Bearer ".Length..].Trim();
        var handler = new JwtSecurityTokenHandler();
        try
        {
            var jwt = handler.ReadJwtToken(token);
            if (!jwt.Audiences.Contains(audience, StringComparer.Ordinal))
            {
                return new BrowserAuthorization(false, false);
            }
        }
        catch (ArgumentException)
        {
            return new BrowserAuthorization(false, false);
        }

        if (signature is null)
        {
            return new BrowserAuthorization(true, false);
        }

        try
        {
            handler.ValidateToken(token, signature, out _);
            return new BrowserAuthorization(true, true);
        }
        catch (Exception ex) when (ex is SecurityTokenException or ArgumentException)
        {
            return new BrowserAuthorization(false, false);
        }
    }
}
