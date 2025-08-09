using System.Net.Http.Json;
using Bill.Application.Interfaces;
using Bill.Domain;
using MediatR;
using Microsoft.Extensions.Configuration;

namespace Bill.Infrastructure;

public class DiscordNotificationService(IConfiguration configuration, HttpClient httpClient) : INotificationService
{
    private readonly string _webhookUrl = configuration["Discord:Webhook:Url"] ?? throw new InvalidOperationException("Discord:Webhook:Url is not set");

    public async Task<Unit> SendMessageAsync(Message message, CancellationToken cancellationToken)
    {
        var embed = new
        {
            author = new { name = "New Bill" },
            title = message.Company,
            description = message.Subject,
            fields = new[]
            {
                new { name = "Due Date", value = message.Date.ToString("yyyy-MM-dd"), inline = true },
                new { name = "Amount", value = $"${message.Amount:F2}", inline = true },
                new { name = "Split", value = $"${message.Amount / 2:F2}", inline = true }
            }
        };

        var payload = new
        {
            username = "Bill",
            embeds = new[] { embed }
        };
        
        await httpClient.PostAsJsonAsync(_webhookUrl, payload, cancellationToken);
        
        return Unit.Value;
    }
}