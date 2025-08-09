namespace Bill.Domain;

public class Message
{
    public required string Subject { get; set; }
    public required string Company { get; set; }
    public required DateOnly Date { get; set; }
    public required decimal Amount { get; set; }
}
