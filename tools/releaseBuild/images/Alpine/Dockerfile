FROM mcr.microsoft.com/powershell:alpine-3.12

RUN apk update \
    && apk add build-base gcc abuild binutils git python3 bash cmake

ENTRYPOINT [ "pwsh" ]
