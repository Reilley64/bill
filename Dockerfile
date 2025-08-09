# Learn about building .NET container images:
# https://github.com/dotnet/dotnet-docker/blob/main/samples/README.md
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0-alpine AS build
ARG TARGETARCH
WORKDIR /source

# Copy project file and restore as distinct layers
COPY --link Bill.sln .
COPY --link Api/Api.csproj Api/Api.csproj
COPY --link Application/Application.csproj Application/Application.csproj
COPY --link Domain/Domain.csproj Domain/Domain.csproj
COPY --link Infrastructure/Infrastructure.csproj Infrastructure/Infrastructure.csproj
RUN dotnet restore -a $TARGETARCH

# Copy source code and publish app
COPY --link . .
RUN dotnet publish Api/Api.csproj -a $TARGETARCH --no-restore -o /app

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0-alpine
EXPOSE 8080
WORKDIR /app
COPY --link --from=build /app .
USER $APP_UID
ENTRYPOINT ["./Api"]
