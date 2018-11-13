FROM mcr.microsoft.com/powershell:6.1.0-alpine-3.8

RUN apk update \
    && apk add build-base gcc abuild binutils git python bash cmake

ENTRYPOINT [ "pwsh" ]
