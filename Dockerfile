FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build

RUN apk update \
    && apk add build-base gcc abuild binutils git python3 bash cmake \
    && apk upgrade

COPY . .

RUN pwsh -c "Import-Module ./build.psm1; Start-BuildNativeUnixBinaries";

FROM scratch AS export
COPY --from=build /src/powershell-unix/libpsl-native.so /libpsl-native.so
