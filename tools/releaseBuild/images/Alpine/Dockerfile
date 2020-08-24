FROM mcr.microsoft.com/powershell:lts-alpine-3.10

RUN apk update \
    && apk add build-base gcc abuild binutils git python bash cmake

ENTRYPOINT [ "pwsh" ]
