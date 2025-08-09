using System.Reflection;
using System.Text;
using System.Text.Json;
using Amazon.BedrockRuntime;
using Amazon.BedrockRuntime.Model;
using Amazon.SecretsManager;
using Bill.Application.Interfaces;
using Bill.Domain;
using iText.Kernel.Pdf;
using iText.Kernel.Pdf.Canvas.Parser;
using Microsoft.Extensions.Configuration;
using Message = Bill.Domain.Message;

namespace Bill.Infrastructure;

public class AmazonBedrockService(IConfiguration configuration, IAmazonBedrockRuntime bedrockClient) : IAgentService
{
    private const string ResponseSchemaResource = "Bill.Infrastructure.Schemas.agent-response-schema.json";
    
    private readonly string _modelId = configuration["AWS:Bedrock:ModelId"] ?? throw new InvalidOperationException("AWS:Bedrock:ModelId is not set");

    public async Task<List<Message>> ProcessAttachmentsAsync(IEnumerable<Attachment> attachments, CancellationToken cancellationToken)
    {
        var responseSchema = await GetResponseSchemaAsync(cancellationToken);
        
        var prompt = $"""
                      Analyze these bill/invoice document(s) and extract information from each one.

                      For each document, extract:
                      1. Subject/Description of the bill
                      2. Company name or service provider issuing the bill
                      3. Date the bill is due
                      4. Total amount to be paid (as a decimal number)

                      Return your response as a JSON array that conforms to this schema:
                      {responseSchema}
                      
                      Rules:
                      - If you cannot determine the subject for a document, use "Unknown"
                      - If you cannot determine the company for a document, use "Unknown"
                      - If you cannot determine the date for a document, use today's date
                      - If you cannot determine the amount for a document, use 0.0
                      - Return exactly one object for each document
                      - Return ONLY the JSON array, no additional text or explanation
                      """;
        
        var content = new List<object>
        {
            new
            {
                type = "text",
                text = prompt,
            }
        };
        content.AddRange(attachments.Select(a => new
        {
            type = "text",
            text = $"\n--- Document: {a.FileName} ---\n{GetPdfText(a.Content)}\n--- End Document ---\n"
        }));

        var request = new InvokeModelRequest
        {
            ModelId = _modelId,
            ContentType = "application/json",
            Body = new MemoryStream(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new
            {
                anthropic_version = "bedrock-2023-05-31",
                max_tokens = 5000,
                messages = new[]
                {
                    new
                    {
                        role = "user",
                        content
                    }
                }
            })))
        };
        
        var response = await bedrockClient.InvokeModelAsync(request, cancellationToken);
        
        using var reader = new StreamReader(response.Body);
        var responseBody = await reader.ReadToEndAsync(cancellationToken);
        
        var agentResponse = JsonSerializer.Deserialize<JsonElement>(responseBody);
        if (!agentResponse.TryGetProperty("content", out var responseContents)) throw new Exception("Invalid response from agent");
        var responseContent = responseContents.EnumerateArray().FirstOrDefault();
        if (!responseContent.TryGetProperty("text", out var jsonString)) throw new Exception("Invalid response from agent");
        
        return JsonSerializer.Deserialize<List<Message>>(jsonString.GetString()!)!;
    }

    private static async Task<string> GetResponseSchemaAsync(CancellationToken cancellationToken)
    {
        var assembly = Assembly.GetExecutingAssembly();
        await using var stream = assembly.GetManifestResourceStream(ResponseSchemaResource);
        using var reader = new StreamReader(stream!);
        return await reader.ReadToEndAsync(cancellationToken);
    }
    
    private static string GetPdfText(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes);
        using var pdfReader = new PdfReader(stream);
        using var pdfDocument = new PdfDocument(pdfReader);
        
        var textBuilder = new StringBuilder();

        for (var i = 1; i <= pdfDocument.GetNumberOfPages(); i++)
        {
            var page = pdfDocument.GetPage(i);
            var pageText = PdfTextExtractor.GetTextFromPage(page);
            textBuilder.AppendLine(pageText);
        }

        return textBuilder.ToString();
    }
}