using Bill.Domain;

namespace Bill.Application.Interfaces;

public interface IAgentService
{
    Task<List<Message>> ProcessAttachmentsAsync(IEnumerable<Attachment> attachments, CancellationToken cancellationToken);
}


