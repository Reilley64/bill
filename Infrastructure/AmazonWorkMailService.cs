using Bill.Application.Interfaces;
using MailKit;
using MailKit.Net.Imap;
using MailKit.Search;
using Microsoft.Extensions.Configuration;
using MimeKit;

namespace Bill.Infrastructure;

public class AmazonWorkMailService(IConfiguration configuration) : IEmailService
{
    private readonly string _username = configuration["AWS:WorkMail:Username"] ?? throw new InvalidOperationException("AWS:WorkMail:Username is not set");
    private readonly string _password = configuration["AWS:WorkMail:Password"] ?? throw new InvalidOperationException("AWS:WorkMail:Password is not set");

    public async Task<Domain.Email[]> GetUnseenEmailsAsync(CancellationToken cancellationToken)
    {
        using var client = new ImapClient();
        await client.ConnectAsync("imap.mail.us-east-1.awsapps.com", 993, true, cancellationToken);

        try
        {
            await client.AuthenticateAsync(_username, _password, cancellationToken);

            var inbox = client.Inbox;
            await inbox.OpenAsync(FolderAccess.ReadWrite, cancellationToken);

            var uids = await inbox.SearchAsync(SearchQuery.NotSeen, cancellationToken);

            var messages = new List<MimeMessage>();
            foreach (var uid in uids)
            {
                var message = await inbox.GetMessageAsync(uid, cancellationToken);
                await inbox.AddFlagsAsync(uid, MessageFlags.Seen, true, cancellationToken);
                messages.Add(message);
            }

            return await Task.WhenAll(messages
                .Select(async m =>
                    new Domain.Email
                    {
                        Subject = m.Subject,
                        Content = m.TextBody,
                        Attachments = await Task.WhenAll(m.Attachments
                            .OfType<MimePart>()
                            .Select(async a =>
                            {
                                using var stream = new MemoryStream();
                                await a.Content.DecodeToAsync(stream, cancellationToken);
                                return new Domain.Attachment
                                {
                                    FileName = a.FileName,
                                    Content = stream.ToArray()
                                };
                            }))
                    }
                ));
        }
        finally
        {
            await client.DisconnectAsync(true, cancellationToken);
        }
    }
}