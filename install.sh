#!/usr/bin/env bash

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
pwd=$(cd "$(dirname "$0")" && pwd)
ln -s $pwd/wtf.py /usr/local/bin/wtf
chmod +x /usr/local/bin/wtf
ln -s $pwd/wtf_script.py /usr/local/bin/wtf.script
chmod +x /usr/local/bin/wtf.script
ln -s $pwd/wtf.sh $HOME/.wtf.sh
ln -s $pwd/uninstall.sh /usr/local/bin/wtf.uninstall
chmod +x /usr/local/bin/wtf.uninstall

##add wtf.sh to bashrc
if ! grep -q "wtf.sh" ~/.bashrc; then
    echo "source $HOME/.wtf.sh" >> ~/.bashrc
fi

source ~/.bashrc