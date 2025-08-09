using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Microsoft.Extensions.Configuration;

namespace Bill.Infrastructure;

public class AmazonSecretsManagerConfigurationProvider(IAmazonSecretsManager secretsManager) : ConfigurationProvider
{
    public override void Load()
    {
        LoadSecretAsync("AWS:WorkMail:Password", "bill/aws/workmail/password").GetAwaiter().GetResult();
        LoadSecretAsync("Discord:Webhook:Url", "bill/discord/webhook/url").GetAwaiter().GetResult();
    }
    
    private async Task LoadSecretAsync(string key, string secretId)
    {
        var response = await secretsManager.GetSecretValueAsync(new GetSecretValueRequest { SecretId = secretId });
        Data[key] = response.SecretString;
    }
}

public class AmazonSecretsManagerConfigurationSource(IAmazonSecretsManager secretsManager) : IConfigurationSource
{
    public IConfigurationProvider Build(IConfigurationBuilder builder)
    {
        return new AmazonSecretsManagerConfigurationProvider(secretsManager);
    }
}
