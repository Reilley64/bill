using Amazon.BedrockRuntime;
using Amazon.SecretsManager;
using Bill.Application.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Bill.Infrastructure;

public static class DependencyInjection
{
    public static void AddInfrastructure(this IServiceCollection services)
    {
        services.AddAWSService<IAmazonSecretsManager>();
        services.AddAWSService<IAmazonBedrockRuntime>();
        
        services.AddHttpClient();
        
        services.AddScoped<IEmailService, AmazonWorkMailService>();
        services.AddScoped<IAgentService, AmazonBedrockService>();
        services.AddScoped<INotificationService, DiscordNotificationService>();
    }
    
    public static void AddSecretsManager(this IServiceCollection services, IConfigurationBuilder builder)
    {
        using var serviceProvider = services.BuildServiceProvider();
        var secretsManager = serviceProvider.GetRequiredService<IAmazonSecretsManager>();
        
        builder.Add(new AmazonSecretsManagerConfigurationSource(secretsManager));
    }
}