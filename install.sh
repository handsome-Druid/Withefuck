#!/usr/bin/env bash
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Set and display installation and home directory
pwd=$(cd "$(dirname "$0")" && pwd)
echo "install_dir : $pwd"
echo "Home : $HOME"


# Create profile links and set permissions
ln -sf $pwd/wtf_profile.sh $HOME/.wtf_profile.sh
chmod +x $HOME/.wtf_profile.sh
ln -sf $pwd/wtf.sh $HOME/.wtf.sh

# Set execute permissions for main scripts
chmod +x $pwd/wtf.py
chmod +x $pwd/wtf_script.py
chmod +x $pwd/uninstall.sh


#Create symlinks in /usr/local/bin for ash
ln -sf $pwd/wtf.py /usr/local/bin/wtf.py
ln -sf $pwd/wtf_script.py /usr/local/bin/wtf_script.py
ln -sf $pwd/uninstall.sh /usr/local/bin/uninstall.sh

# Add sourcing to .bashrc, .zshrc, .ashrc if they exist
for rcfile in ~/.bashrc ~/.zshrc ~/.ashrc; do
    if [ -f "$rcfile" ]; then
        # 对 ash 用 "."，对 bash/zsh 用 "source"
        if ! echo "$rcfile" | grep -q "bashrc"; then
            if echo "$rcfile" | grep -q "ashrc"; then
                src_cmd="."
            else
                src_cmd="source"
            fi
        else 
            src_cmd="source"
        fi

        if ! grep -q "wtf.sh" "$rcfile"; then
            echo "$src_cmd $HOME/.wtf.sh" >> "$rcfile"
        fi
        if ! grep -q "wtf_profile.sh" "$rcfile"; then
            echo "$src_cmd $HOME/.wtf_profile.sh" >> "$rcfile"
        fi
    fi
done

# Source the scripts
source $HOME/.wtf.sh
source $HOME/.wtf_profile.sh

# Run initial configuration
$pwd/wtf.py --config





echo "Withefuck has been installed successfully."
echo "Please run:"
echo
echo "      . ~/.wtf_profile.sh && . ~/.wtf.sh"
echo
echo "or restart your terminal session to start logging."