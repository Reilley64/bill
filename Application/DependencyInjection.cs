using System.Reflection;
using Microsoft.Extensions.DependencyInjection;

namespace Bill.Application;

public static class DependencyInjection
{
    public static void AddApplication(this IServiceCollection services)
    {
        services.AddMediatR(x => x.RegisterServicesFromAssembly(Assembly.GetExecutingAssembly()));
    }
}