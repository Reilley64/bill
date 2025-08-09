using Bill.Domain;
using MediatR;

namespace Bill.Application.Interfaces;

public interface INotificationService
{
    Task<Unit> SendMessageAsync(Message message, CancellationToken cancellationToken);
}


