namespace Bill.Domain;

public class Attachment
{
    public required string FileName { get; set; }
    public required byte[] Content { get; set; }
}
