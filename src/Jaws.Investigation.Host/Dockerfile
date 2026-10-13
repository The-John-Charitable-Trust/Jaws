# Build from repository root: docker build --platform linux/amd64 -f src/Jaws.Investigation.Host/Dockerfile -t jaws-investigation:local .
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY src/Jaws.Investigation/Jaws.Investigation.csproj src/Jaws.Investigation/
COPY src/Jaws.Investigation.Host/Jaws.Investigation.Host.csproj src/Jaws.Investigation.Host/
RUN dotnet restore src/Jaws.Investigation.Host/Jaws.Investigation.Host.csproj
COPY src/Jaws.Investigation/ src/Jaws.Investigation/
COPY src/Jaws.Investigation.Host/ src/Jaws.Investigation.Host/
RUN dotnet publish src/Jaws.Investigation.Host/Jaws.Investigation.Host.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app/publish ./
ENV ASPNETCORE_URLS=http://0.0.0.0:8088
ENV DOTNET_EnableDiagnostics=0
EXPOSE 8088
USER $APP_UID
ENTRYPOINT ["dotnet","Jaws.Investigation.Host.dll"]
