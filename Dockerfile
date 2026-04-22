# syntax=docker/dockerfile:1.7
# Build stage
ARG DOTNET_SDK_VERSION=10.0
ARG DOTNET_RUNTIME_VERSION=10.0
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK_VERSION} AS build
WORKDIR /src

# Copy csproj files first to maximize layer cache
COPY src/Api/Api.csproj src/Api/
COPY tests/Api.Tests/Api.Tests.csproj tests/Api.Tests/
RUN dotnet restore src/Api/Api.csproj

# Copy the rest and publish
COPY src/ src/
RUN dotnet publish src/Api/Api.csproj \
    -c Release \
    -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_RUNTIME_VERSION} AS runtime
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
COPY --from=build /app/publish ./
USER $APP_UID
ENTRYPOINT ["dotnet", "SelfHealingDemo.Api.dll"]
