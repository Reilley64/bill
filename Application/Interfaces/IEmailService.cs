namespace Bill.Application.Interfaces;

public interface IEmailService
{
    Task<Domain.Email[]> GetUnseenEmailsAsync(CancellationToken cancellationToken);
}
