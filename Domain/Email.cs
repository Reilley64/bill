namespace Bill.Domain;

public class Email
{
    public required string Subject { get; set; }
    public string? Content { get; set; }
    public IEnumerable<Attachment> Attachments { get; set; } = [];
}