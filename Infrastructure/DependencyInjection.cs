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
        services.AddAWSService<IAmazonBedrockRuntime>();
        
        services.AddHttpClient();
        
        services.AddScoped<IEmailService, AmazonWorkMailService>();
        services.AddScoped<IAgentService, AmazonBedrockService>();
        services.AddScoped<INotificationService, DiscordNotificationService>();
    }
}