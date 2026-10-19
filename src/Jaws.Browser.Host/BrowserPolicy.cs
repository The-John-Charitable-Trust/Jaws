namespace Jaws.Browser.Host;

internal static class BrowserPolicy
{
    public static bool IsAllowed(string targetText, IEnumerable<string> allowList)
    {
        if (!Uri.TryCreate(targetText, UriKind.Absolute, out var target))
        {
            return false;
        }
        if (target.Scheme is not ("https" or "http") || !string.IsNullOrEmpty(target.UserInfo))
        {
            return false;
        }
        foreach (var raw in allowList)
        {
            if (!Uri.TryCreate(raw, UriKind.Absolute, out var allowed))
            {
                continue;
            }
            if (!string.Equals(target.Scheme, allowed.Scheme, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(target.IdnHost, allowed.IdnHost, StringComparison.OrdinalIgnoreCase) ||
                target.Port != allowed.Port)
            {
                continue;
            }
            var allowedPath = allowed.AbsolutePath.TrimEnd('/');
            var targetPath = target.AbsolutePath.TrimEnd('/');
            if (targetPath.Equals(allowedPath, StringComparison.OrdinalIgnoreCase) ||
                targetPath.StartsWith(allowedPath + "/", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    public static bool IsCredentialField(string selector)
    {
        return selector.Contains("password", StringComparison.OrdinalIgnoreCase) ||
            selector.Contains("passwd", StringComparison.OrdinalIgnoreCase) ||
            selector.Contains("secret", StringComparison.OrdinalIgnoreCase) ||
            selector.Contains("token", StringComparison.OrdinalIgnoreCase);
    }
}
