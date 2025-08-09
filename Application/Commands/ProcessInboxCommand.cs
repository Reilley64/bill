using Bill.Application.Interfaces;
using MediatR;

namespace Bill.Application.Commands;

public record ProcessInboxCommand : IRequest<Unit>;

public class ProcessInboxHandler(IEmailService emailService, IAgentService agentService, INotificationService notificationService) : IRequestHandler<ProcessInboxCommand, Unit>
{
    public async Task<Unit> Handle(ProcessInboxCommand request, CancellationToken cancellationToken)
    {
        var emails = await emailService.GetUnseenEmailsAsync(cancellationToken);
        if (emails.Length == 0) return Unit.Value;
        
        var messages = await agentService.ProcessAttachmentsAsync(emails.SelectMany(e => e.Attachments), cancellationToken);

        foreach (var message in messages)
        {
            await notificationService.SendMessageAsync(message, cancellationToken);
        }
        
        return Unit.Value;
    }
}
