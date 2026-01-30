FROM onebranch.azurecr.io/linux/rockylinux:latest AS build

RUN dnf update
RUN dnf install -y gcc git python3 cmake gcc-c++ rpm-build

COPY . .

RUN pwsh -c "Import-Module ./build.psm1; Start-BuildNativeUnixBinaries";

FROM scratch AS export
COPY --from=build /src/powershell-unix/libpsl-native.so /libpsl-native.so
