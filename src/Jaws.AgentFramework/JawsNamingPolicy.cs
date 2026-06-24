namespace Jaws.AgentFramework.Installation;

public sealed record NamingInputs(
    string Organization,
    string Environment,
    string Region,
    string Workload = "jaws",
    string? Prefix = null,
    string? Suffix = null);

public sealed record GeneratedResourceNames(
    string ResourceGroup,
    string AppService,
    string AppServicePlan,
    string KeyVault,
    string LogAnalyticsWorkspace,
    string ApplicationInsights,
    string StorageAccount);

public static class JawsNamingPolicy
{
    public static GeneratedResourceNames Generate(NamingInputs inputs)
    {
        var parts = new[]
        {
            NormalizeSegment(inputs.Prefix),
            NormalizeSegment(inputs.Organization),
            NormalizeSegment(inputs.Workload),
            NormalizeSegment(inputs.Environment),
            NormalizeSegment(inputs.Region),
            NormalizeSegment(inputs.Suffix)
        }.Where(static value => !string.IsNullOrWhiteSpace(value)).ToArray();

        var regionalName = string.Join('-', parts);
        var nonRegionalParts = parts
            .Where(part => !string.Equals(part, NormalizeSegment(inputs.Region), StringComparison.OrdinalIgnoreCase))
            .ToArray();
        var nonRegionalName = string.Join('-', nonRegionalParts);
        var storageName = NormalizeStorageName(string.Concat(nonRegionalParts));

        return new GeneratedResourceNames(
            ResourceGroup: $"rg-{regionalName}",
            AppService: $"app-{regionalName}",
            AppServicePlan: $"asp-{regionalName}",
            KeyVault: TrimAzureName($"kv-{nonRegionalName}", 24),
            LogAnalyticsWorkspace: $"law-{regionalName}",
            ApplicationInsights: $"appi-{regionalName}",
            StorageAccount: storageName);
    }

    private static string NormalizeSegment(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var chars = value
            .Trim()
            .ToLowerInvariant()
            .Select(ch => char.IsLetterOrDigit(ch) ? ch : '-')
            .ToArray();

        return string.Join('-', new string(chars)
            .Split('-', StringSplitOptions.RemoveEmptyEntries));
    }

    private static string NormalizeStorageName(string value)
    {
        var normalized = new string(value
            .ToLowerInvariant()
            .Where(char.IsLetterOrDigit)
            .ToArray());

        if (normalized.Length < 3)
        {
            normalized = normalized.PadRight(3, '0');
        }

        return normalized[..Math.Min(normalized.Length, 24)];
    }

    private static string TrimAzureName(string value, int maxLength) =>
        value.Length <= maxLength ? value : value[..maxLength].TrimEnd('-');
}
