using Bill.Application.Commands;
using MediatR;
using MediatR.BackgroundService;
using Microsoft.AspNetCore.Mvc;

namespace Api.Controllers;

[ApiController]
[Route("[controller]")]
public class InboxController(IMediatorBackground backgroundService) : ControllerBase
{
    [HttpPost]
    public async Task<Unit> Post()
    {
        await backgroundService.Send(new ProcessInboxCommand());
        return Unit.Value;
    }
}