#!/bin/bash

WORKDIR=$(pwd)
CUR_ARCH=$(uname -m)
DIST="jessie"
ARCH="x86_64"
OUTPUT=${WORKDIR}/debootstrap-${ARCH}-${DIST}

# 额外安装的软件包列表，逗号分隔
EXTRA_PACKAGE="vim,git,openssh-server,build-essential,command-not-found,tmux,iproute2,net-tools"


if [ "${CUR_ARCH}" != "${ARCH}" ]
then
	echo " Error: This scripts just support arch:${ARCH}"
	exit 1
fi

if ! which debootstrap &> /dev/null
then
	echo " Error: debootstrap not found!"
	echo " You can run 'sudo yum install -y debootstrap' to install it"
	exit 1
fi

if [ $# -eq 0 ]
then
	if [ -d "${OUTPUT}" ]
	then
		echo " Warnning: Already exists ${OUTPUT}, clean it at first!"
		exit 1
	fi
	debootstrap --arch=amd64 \
		--no-check-gpg \
		--include="${EXTRA_PACKAGE}" \
		"${DIST}" \
		"${OUTPUT}" \
		https://mirrors.tuna.tsinghua.edu.cn/debian

	if [ $? -ne 0 ]
	then
		echo " Error : debootstrap return no zero! check it."
		exit 1
	fi
fi

if [ ! -d "${OUTPUT}" ]
then
	echo " Warnning: ${OUTPUT} doesn't exists! debootstrap it at first!"
	exit 1
fi

########################################
# 其他修改操作
########################################

# 修改root密码，不创建其他用户
sed -i '1s#.*#root:$y$j9T$quJBgpxet.41ZYrTPIXIt0$ogsvsdrOZrP3OTZ.OVIpaFpOeCu4Bkp3J9RQawpfuJ6:19221:0:99999:7:::#'  "${OUTPUT}/etc/shadow"
echo " * set root password : linux"
# 修改主机名
echo "linux3-x64" > "${OUTPUT}/etc/hostname"
echo " * set hostname : linux3-x64"
# 修改bash环境
cat >> "${OUTPUT}/etc/profile" << EOF

# alias
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias grep='grep --color=auto'
alias l.='ls -d .* -a --color=auto'
alias ll='ls -l -h -a --color=auto'
alias ls='ls -a --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias xzegrep='xzegrep --color=auto'
alias xzfgrep='xzfgrep --color=auto'
alias xzgrep='xzgrep --color=auto'
alias zegrep='zegrep --color=auto'
alias zfgrep='zfgrep --color=auto'
alias zgrep='zgrep --color=auto'
alias push='git push'


# History setting
export PROMPT_COMMAND="history -a"
export HISTTIMEFORMAT="%F %T "
export HISTSIZE=10000

# Proxy settings
#export http_proxy='127.0.0.1:5050'
#export https_proxy='127.0.0.1:5050'
#export ftp_proxy='127.0.0.1:5050'

#export http_proxy=
#export https_proxy=
#export ftp_proxy=


PS1='\[\e[32;1m\][\[\e[31;1m\]\u\[\e[33;1m\]@\[\e[35;1m\]\h\[\e[36;1m\] \w\[\e[32;1m\]]\[\e[37;1m\]\\\$\[\e[0m\] '
EOF
echo " * config bash environment"


echo "All done! All is well!"

