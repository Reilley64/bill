using Bill.Application;
using Bill.Application.Commands;
using Bill.Infrastructure;
using MediatR;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);

builder.Configuration
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true)
    .AddUserSecrets<Program>()
    .AddEnvironmentVariables();

// Add services to the container.
builder.Services.AddInfrastructure();
builder.Services.AddApplication();

var host = builder.Build();

using var scope = host.Services.CreateScope();
var mediator =  scope.ServiceProvider.GetRequiredService<IMediator>();

await mediator.Send(new ProcessInboxCommand());
Environment.Exit(0);
