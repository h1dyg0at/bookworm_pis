#!/bin/bash
# Debian post-install script

if lsb_release -cs | grep -qE -e "bookworm"; then
  ver=bookworm
else
  echo "Currently only Debian 12 supported!"
  exit 1
fi

is_docker=0
if [ -f /.dockerenv ]; then
  echo "Note: we are running inside Docker container, so some adjustings will be applied!"
  is_docker=1
fi

dpkg_arch=$(dpkg --print-architecture)
if [[ "$dpkg_arch" == "amd64" || "$dpkg_arch" == "armhf" || "$dpkg_arch" == "arm64" ]]; then
  echo "Detected CPU architecture is $dpkg_arch, it is supported."
else
  echo "Currently only amd64 (x86_64), armhf and arm64 CPU architectures are supported!"
  exit 2
fi

if [ "$UID" -ne "0" ]
then
  echo "Please run this script as root user with 'sudo -E ./umpis.sh'"
  exit 3
fi

echo "Welcome to the bookworm post-install script!"
set -e
set -x

# Initialize
export DEBIAN_FRONTEND=noninteractive

# Configure MATE desktop
if [[ $is_docker == 0 && "$DESKTOP_SESSION" == "mate" ]]; then
## terminal
cat <<EOF > /tmp/dconf-mate-terminal
[keybindings]
help='disabled'

[profiles/default]
allow-bold=false
background-color='#FFFFFFFFDDDD'
palette='#2E2E34343636:#CCCC00000000:#4E4E9A9A0606:#C4C4A0A00000:#34346565A4A4:#757550507B7B:#060698209A9A:#D3D3D7D7CFCF:#555557575353:#EFEF29292929:#8A8AE2E23434:#FCFCE9E94F4F:#72729F9FCFCF:#ADAD7F7FA8A8:#3434E2E2E2E2:#EEEEEEEEECEC'
bold-color='#000000000000'
foreground-color='#000000000000'
visible-name='Default'
scrollback-unlimited=true
EOF

sudo -EHu "$SUDO_USER" -- dconf load /org/mate/terminal/ < /tmp/dconf-mate-terminal

fi # (is_docker && MATE)?

# Setup the system
rm -v /var/lib/dpkg/lock* /var/cache/apt/archives/lock || true
systemctl stop unattended-upgrades.service || true
apt-get purge unattended-upgrades -y || true

systemctl stop ua-messaging.timer || true
systemctl stop ua-messaging.service || true
systemctl mask ua-messaging.timer || true
systemctl mask ua-messaging.service || true

echo 'APT::Periodic::Enable "0";' > /etc/apt/apt.conf.d/99periodic-disable

systemctl stop apt-daily.service || true
systemctl stop apt-daily.timer || true
systemctl stop apt-daily-upgrade.timer || true
systemctl stop apt-daily-upgrade.service || true
systemctl mask apt-daily.service || true
systemctl mask apt-daily.timer || true
systemctl mask apt-daily-upgrade.timer || true
systemctl mask apt-daily-upgrade.service || true

sed -i "s/^enabled=1/enabled=0/" /etc/default/apport || true
sed -i "s/^Prompt=normal/Prompt=never/" /etc/update-manager/release-upgrades || true
sed -i "s/^Prompt=lts/Prompt=never/" /etc/update-manager/release-upgrades || true

# Install updates
rm -vrf /var/lib/apt/lists/* || true

apt-get update
apt-get install -f -y
apt-get dist-upgrade -o DPkg::Options::=--force-confdef --force-yes -y
apt-get install -f -y
dpkg --configure -a

# add-apt-repository, wget
apt-get install -y wget
apt-get install -y python3-launchpadlib

# Restricted extras
apt-get install -y ubuntu-restricted-addons ubuntu-restricted-extras || true

# Git
apt-get install -y git

apt-get install -y rabbitvcs-cli python3-caja python3-tk git mercurial subversion
if [ $is_docker == 0 ]; then
  sudo -u "$SUDO_USER" -- mkdir -p ~/.local/share/caja-python/extensions
  cd ~/.local/share/caja-python/extensions
  sudo -u "$SUDO_USER" -- wget -c https://raw.githubusercontent.com/rabbitvcs/rabbitvcs/v0.18/clients/caja/RabbitVCS.py
else
  mkdir -p /usr/local/share/caja-python/extensions
  wget -c https://raw.githubusercontent.com/rabbitvcs/rabbitvcs/v0.18/clients/caja/RabbitVCS.py -O /usr/local/share/caja-python/extensions/RabbitVCS.py
fi

apt-get install apt-file
apt install apt-xapian-index
update-apt-xapian-index
apt-file update
apt-get install software-properties-common python3-launchpadlib
add-apt-repository -y main contrib non-free non-free-firmware

# Kate text editor
apt-get install -y kate


# LibreOffice
apt-get update
apt-get install libreoffice -y
apt-get dist-upgrade -y
apt-get install -f -y
apt-get dist-upgrade -y


# ReText
apt-get install -y retext

if [ $is_docker == 0 ]; then
  mkdir -p ~/.config
  chown -R "$SUDO_USER":  ~/.config
  echo mathjax | sudo -u "$SUDO_USER" -- tee -a ~/.config/markdown-extensions.txt
  chown "$SUDO_USER": ~/.config/markdown-extensions.txt
else
  echo mathjax >> /etc/skel/.config/markdown-extensions.txt
fi

# PlayOnLinux
dpkg --add-architecture i386
apt-get update
apt-get install -y wine32 || true
apt-get install -y playonlinux winetricks

# Y PPA Manager, install gawk to prevent LP#2036761
apt-get install -y ppa-purge gawk || true

# Install locale packages
apt-get install -y locales
apt-get install -y $(check-language-support -l en) $(check-language-support -l ru) || true
apt-get install -y --reinstall --install-recommends task-russian task-russian-desktop || true

# Ubuntu Make
if [ $is_docker == 0 ] ; then
  umake_path=umake

  apt-get install -y snapd
  systemctl unmask snapd.seeded snapd
  systemctl enable snapd.seeded snapd
  systemctl start snapd.seeded snapd

  snap install ubuntu-make --classic --edge
  snap refresh ubuntu-make --classic --edge

  umake_path=/snap/bin/umake

  # need to use SDDM on Debian because of https://github.com/ubuntu/ubuntu-make/issues/678
  apt-get install -y --reinstall sddm --no-install-recommends --no-install-suggests
  unset DEBIAN_FRONTEND
  dpkg-reconfigure sddm
  export DEBIAN_FRONTEND=noninteractive
fi

# fixes for Bullseye, Bookworm, Jammy and Noble
if [[ "$ver" == "bullseye" || "$ver" == "bookworm" || "$ver" == "jammy" || "$ver" == "noble" ]]; then
  # Readline fix for LP#1926256 bug
  if [ $is_docker == 0 ]; then
    echo "set enable-bracketed-paste Off" | sudo -u "$SUDO_USER" tee -a ~/.inputrc
  else
    echo "set enable-bracketed-paste Off" | tee -a /etc/inputrc
  fi
  # VTE fix for LP#1922276 bug
  apt-key adv --keyserver keyserver.ubuntu.com --recv E756285F30DB2B2BB35012E219BFCAF5168D33A9
  add-apt-repository -y "deb http://ppa.launchpad.net/nrbrtx/vte/ubuntu jammy main"
  apt-get update
  apt-get dist-upgrade -y
fi

# fixes for Bookworm, Jammy and Noble (see LP#1947420)
if [[ "$ver" == "bookworm" || "$ver" == "jammy" || "$ver" == "noble" ]]; then
  apt-key adv --keyserver keyserver.ubuntu.com --recv E756285F30DB2B2BB35012E219BFCAF5168D33A9
  add-apt-repository -y "deb http://ppa.launchpad.net/nrbrtx/wnck/ubuntu jammy main"
  apt-get update
  apt-get dist-upgrade -y
fi


# Remove possibly installed WSL utilites
apt-get purge -y wslu || true

# Cleaning up
apt-get autoremove -y

# Looks like mate
add-apt-repository -y "deb http://ppa.launchpad.net/nrbrtx/dmas/ubuntu jammy main"
apt-get install --no-install-recommends debian-mate-ayatana-settings


echo "Ubuntu MATE (and Debian) post-install script finished! Reboot to apply all new settings and enjoy newly installed software."

exit 0

#A huge thank you to my teacher N0rbert

