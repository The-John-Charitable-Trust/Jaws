# Linux/amd64 browser control service. No public ingress is added by the installer.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Jaws.Browser.Host.csproj ./
RUN dotnet restore ./Jaws.Browser.Host.csproj
COPY *.cs ./
RUN dotnet publish ./Jaws.Browser.Host.csproj -c Release -o /app/out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends chromium \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/out ./
ENV ASPNETCORE_URLS=http://0.0.0.0:8089
ENV DOTNET_EnableDiagnostics=0
ENV JAWS_BROWSER_CHROMIUM_PATH=/usr/bin/chromium
EXPOSE 8089
USER $APP_UID
ENTRYPOINT ["dotnet","Jaws.Browser.Host.dll"]
