FROM debian:jessie

COPY bashrc /root/.bashrc
COPY sources.list /etc/apt/sources.list
RUN apt-get update && \
	apt-get install -y --force-yes vim gcc build-essential make \
		libncurses-dev \
		apt-file \
		xfsprogs \
		file git flex bison \
		bc libelf-dev libssl-dev && \
	rm -rf /etc/localtime && \
	ln -vfs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime


