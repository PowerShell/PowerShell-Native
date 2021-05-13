FROM mcr.microsoft.com/powershell:centos-7

LABEL maintainer="PowerShell Team <powershellteam@hotmail.com>"

RUN yum install -y \
	which \
	git \
	sudo \
	&& yum clean all

ENTRYPOINT [ "pwsh" ]
