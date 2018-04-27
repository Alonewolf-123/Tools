#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE="veda.conf"
VEDA_DAEMON="/usr/local/bin/vedad"
VEDA_REPO="https://github.com/Veda-Coin/VedaCore.git"
DEFAULTVEDAPORT=21992
DEFAULTVEDAUSER="veda"
NODEIP=$(curl -s4 icanhazip.com)


RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $@. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $VEDA_DAEMON)" ] || [ -e "$VEDA_DAEMOM" ] ; then
  echo -e "${GREEN}\c"
  read -e -p "Veda is already installed. Do you want to add another Miner? [Y/N]" NEW_VEDA
  echo -e "{NC}"
  clear
else
  NEW_VEDA="new"
fi
echo -e "${NC}"
apt-get update
apt-get upgrade
apt-get install libboost-system1.58.0
apt-get install libboost-filesystem1.58.0
apt-get install libboost-program-options1.58.0
apt-get install libboost-thread1.58.0
apt-get install libboost-chrono1.58.0
apt-get install libminiupnpc10
apt-get install libzmq5
apt-get install libevent-2.0-5
apt-get install libevent-pthreads-2.0-5
apt-get install pwgen
apt-get install bc
}

function prepare_system() {

echo -e "Prepare the system to install Veda master node."
apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${GREEN}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev ufw fail2ban >/dev/null 2>&1
clear
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git pwgen curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw fail2ban "
 exit 1
fi

clear
echo -e "Checking if swap space is needed."
PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
SWAP=$(free -g|awk '/^Swap:/{print $2}')
if [ "$PHYMEM" -lt "2" ] && [ -n "$SWAP" ]
  then
    echo -e "${GREEN}Server is running with less than 2G of RAM without SWAP, creating 2G swap file.${NC}"
    SWAPFILE=$(mktemp)
    dd if=/dev/zero of=$SWAPFILE bs=1024 count=2M
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon -a $SWAPFILE
else
  echo -e "${GREEN}Server running with at least 2G of RAM, no swap needed.${NC}"
fi
clear
}

function install_daemon() {
    echo -e "Download the debian package from Veda git.."
    wget https://github.com/Veda-Coin/VedaCore/releases/download/Veda-Core1.0-1/veda-setup_1.0-1.deb
    sleep 2
    dpkg --install veda-setup_1.0-1.deb
    sleep 1
    vedad &
    sleep 5
}

function compile_node() {
  echo -e "Clone git repo and compile it. This may take some time. Press a key to continue."
  cd $TMP_FOLDER
  git clone https://github.com/Veda-Coin/VedaCore
  cd VedaCore
  chmod +x ./autogen.sh
  ./autogen.sh
  ./configure
  make
  ./tests
  make install
  clear

  cd $TMP_FOLDER
  git clone $VEDA_REPO
  cd Veda/src
  make -f makefile.unix
  compile_error Veda
  chmod +x  vedad
  cp -a  vedad /usr/local/bin
  clear
  cd ~
  rm -rf $TMP_FOLDER
}

function wait_collateral() {
    clear
    echo -e "${GREEN}Please send this address the collateral of 1000 VEDA!${NC}"
    ADDRESS=$(veda-cli getaccountaddress 0)
    echo -e "${RED}$ADDRESS${NC}"
    BALANCE=0
    COLLATERAL=1000.0
    BALANCE=$(veda-cli getbalance)
    if (( $(echo "$BALANCE < $COLLATERAL" | bc -l) )); then
        echo -e "The current balance is ${RED}$BALANCE${NC}"
        echo -e "${GREEN}Please wait until your balance is bigger than 1000 VEDA!${NC}"
    fi
    while (( $(echo "$BALANCE < $COLLATERAL" | bc -l) )); do
        BALANCE=$(veda-cli getbalance)
        sleep 2
    done
    echo -e "The current balance is ${GREEN}$BALANCE${NC}"

}

function enable_firewall() {
  echo -e "Installing fail2ban and setting up firewall to allow ingress on port ${GREEN}$VEDAPORT${NC}"
  ufw allow $VEDAPORT/tcp comment "VEDA MN port" >/dev/null
  ufw allow $[VEDAPORT-1]/tcp comment "VEDA RPC port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
  systemctl enable fail2ban >/dev/null 2>&1
  systemctl start fail2ban >/dev/null 2>&1
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$VEDAUSER.service
[Unit]
Description=VEDA service
After=network.target

[Service]
ExecStart=$VEDA_DAEMON -conf=$VEDAFOLDER/$CONFIG_FILE -datadir=$VEDAFOLDER
ExecStop=$VEDA_DAEMON -conf=$VEDAFOLDER/$CONFIG_FILE -datadir=$VEDAFOLDER stop
Restart=on-abort
User=$VEDAUSER
Group=$VEDAUSER

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $VEDAUSER.service
  systemctl enable $VEDAUSER.service

  if [[ -z "$(ps axo user:15,cmd:100 | egrep ^$VEDAUSER | grep $VEDA_DAEMON)" ]]; then
    echo -e "${RED}VEDA is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $VEDAUSER.service"
    echo -e "systemctl status $VEDAUSER.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}

function ask_port() {
read -p "Veda Port: " -i $DEFAULTVEDAPORT -e VEDAPORT
: ${VEDAPORT:=$DEFAULTVEDAPORT}
}

function ask_user() {
  read -p "Veda user: " -i $DEFAULTVEDAUSER -e VEDAUSER
  : ${VEDAUSER:=$DEFAULTVEDAUSER}

  if [ -z "$(getent passwd $VEDAUSER)" ]; then
    USERPASS=$(pwgen -s 12 1)
    useradd -m $VEDAUSER
    echo "$VEDAUSER:$USERPASS" | chpasswd

    VEDAHOME=$(sudo -H -u $VEDAUSER bash -c 'echo $HOME')
    DEFAULTVEDAFOLDER="$VEDAHOME/.vedacore"
    read -p "Configuration folder: " -i $DEFAULTVEDAFOLDER -e VEDAFOLDER
    : ${VEDAFOLDER:=$DEFAULTVEDAFOLDER}
    mkdir -p $VEDAFOLDER
    chown -R $VEDAUSER: $VEDAFOLDER >/dev/null
  else
    clear
    echo -e "${RED}User exits. Please enter another username: ${NC}"
    ask_user
  fi
}

function check_port() {
  declare -a PORTS
  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $VEDAPORT ]] || [[ ${PORTS[@]} =~ $[VEDAPORT-1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

getMyIP() {
    local _ip _myip _line _nl=$'\n'
    while IFS=$': \t' read -a _line ;do
        [ -z "${_line%inet}" ] &&
           _ip=${_line[${#_line[1]}>4?1:2]} &&
           [ "${_ip#127.0.0.1}" ] && _myip=$_ip
      done< <(LANG=C /sbin/ifconfig)
    printf ${1+-v} $1 "%s${_nl:0:$[${#1}>0?0:1]}" $_myip
}

function create_config() {
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
    echo -e "${RED}rpcuser is${NC} $RPCUSER"
    echo -e "${RED}rpcpassword is${NC} $RPCPASSWORD"
    DEFAULTVEDAFOLDER="$HOME/.vedacore"

    veda-cli stop
    sleep 1

  cat << EOF > $DEFAULTVEDAFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
gen=1
maxconnections=256
EOF
    vedad
    sleep 5
    echo -e "${GREEN}Started Miner!${NC}"
}

function create_key() {
  echo -e "Enter your ${RED}Masternode Private Key${NC}. Leave it blank to generate a new ${RED}Masternode Private Key${NC} for you:"
  read -e VEDAKEY
  if [[ -z "$VEDAKEY" ]]; then
  su $VEDAUSER -c "$VEDA_DAEMON -conf=$VEDAFOLDER/$CONFIG_FILE -datadir=$VEDAFOLDER"
  sleep 5
  if [ -z "$(ps axo user:15,cmd:100 | egrep ^$VEDAUSER | grep $VEDA_DAEMON)" ]; then
   echo -e "${RED}Veda server couldn't start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  VEDAKEY=$(su $VEDAUSER -c "$VEDA_DAEMON -conf=$VEDAFOLDER/$CONFIG_FILE -datadir=$VEDAFOLDER masternode genkey")
  su $VEDAUSER -c "$VEDA_DAEMON -conf=$VEDAFOLDER/$CONFIG_FILE -datadir=$VEDAFOLDER stop"
fi
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $VEDAFOLDER/$CONFIG_FILE
  cat << EOF >> $VEDAFOLDER/$CONFIG_FILE
maxconnections=256
masternode=1
masternodeaddr=$NODEIP:$VEDAPORT
masternodeprivkey=$VEDAKEY
EOF
  chown -R $VEDAUSER: $VEDAFOLDER >/dev/null
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "Veda Masternode is up and running as user ${GREEN}$VEDAUSER${NC} and it is listening on port ${GREEN}$VEDAPORT${NC}."
 echo -e "${GREEN}$VEDAUSER${NC} password is ${RED}$USERPASS${NC}"
 echo -e "Configuration file is: ${RED}$VEDAFOLDER/$CONFIG_FILE${NC}"
 echo -e "Start: ${RED}systemctl start $VEDAUSER.service${NC}"
 echo -e "Stop: ${RED}systemctl stop $VEDAUSER.service${NC}"
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$VEDAPORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$VEDAKEY${NC}"
 echo -e "Please check Veda is running with the following command: ${GREEN}systemctl status $VEDAUSER.service${NC}"
 echo -e "================================================================================================================================"
}


function setup_node() {
clear
  create_config
}


##### Main #####
clear

checks
if [[ ("$NEW_VEDA" == "y" || "$NEW_VEDA" == "Y") ]]; then
  setup_node
  exit 0
elif [[ "$NEW_VEDA" == "new" ]]; then
#  prepare_system
#  compile_node
  install_daemon
  setup_node
else
  echo -e "${GREEN}Veda already running.${NC}"
  exit 0
fi
