# Multi-stage, Linux/amd64 .NET 10 image for Microsoft Foundry hosted agents.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Jaws.Supervisor.Host.csproj ./
RUN dotnet restore ./Jaws.Supervisor.Host.csproj
COPY Program.cs ./
RUN dotnet publish ./Jaws.Supervisor.Host.csproj -c Release -o /app/out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app/out ./
ENV ASPNETCORE_URLS=http://0.0.0.0:8088
ENV DOTNET_EnableDiagnostics=0
EXPOSE 8088
USER $APP_UID
ENTRYPOINT ["dotnet","Jaws.Supervisor.Host.dll"]
