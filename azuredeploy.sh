#!/bin/bash
#should work for all skus
set -x
#set -xeuo pipefail

if [[ $(id -u) -ne 0 ]] ; then
    echo "Must be run as root"
    exit 1
fi

if [ $# != 9 ]; then
    echo "Usage: $0 <clusterdet> <HPCUserName> <mountFolder> <mungedet> <nvidiadet> <numDataDisks> <dockerdet> <imagedet> <artifactsLocation>"
    exit 1
fi


# Set user args
MASTER_HOSTNAME=$( echo "$1" |cut -d\: -f1 )
WORKER_HOSTNAME_PREFIX=$( echo "$1" |cut -d\: -f2 )
WORKER_COUNT=$( echo "$1" |cut -d\: -f3 )
omsworkspaceid=$( echo "$1" |cut -d\: -f4 )
omsworkspacekey=$( echo "$1" |cut -d\: -f5 )
nvidiadockerbinver=$( echo "$1" |cut -d\: -f6 )
HEADNODE_SIZE=$( echo "$1" |cut -d\: -f7 )
WORKERNODE_SIZE=$( echo "$1" |cut -d\: -f8 )
LAST_WORKER_INDEX=$(($WORKER_COUNT - 1))

# Shares
MNT_POINT="$3"
SHARE_HOME=$MNT_POINT/home
SHARE_DATA=$MNT_POINT/data

# Munged
MUNGE_VER=$( echo "$4" |cut -d\: -f1 )
MUNGE_GROUP=$( echo "$4" |cut -d\: -f2 )
TORQUEORPBS=$( echo "$4" |cut -d\: -f3 )
SALTSTACKBOOLEAN=$( echo "$4" |cut -d\: -f4 )


# CUDA and Tesla
TESLA_DRIVER_LINUX=$( echo "$5" |cut -d\: -f2 )
CUDA_VER=$( echo "$5" |cut -d\: -f1 )
CUDA_VERSION=$CUDA_VER

# Hpc User
HPC_USER="$2"
HPC_UID=7007
HPC_GROUP=$HPC_USER
HPC_GID=7007

numberofDisks=$6
dockerVer=$( echo "$7" |cut -d\: -f1 )
dockerComposeVer=$( echo "$7" |cut -d\: -f2 )
dockMVer=$( echo "$7" |cut -d\: -f3 )
userName=$( echo "$8" |cut -d\: -f2 )
skuName=$( echo "$8" |cut -d\: -f1 )
TEMPLATE_BASE_URL=$9


# Returns 0 if this node is the master node.
#
is_master()
{
    hostname | grep "$MASTER_HOSTNAME"
    return $?
}


enable_kernel_update()
{
	if [ "$skuName" == "6.5" ] || [ "$skuName" == "7.1" ]; then
		cd /etc && sed -i.bak -e '28d' yum.conf
		cd /etc && sed -i '28i#exclude=kernel*' yum.conf

	elif [ "$skuName" == "6.6" ] || [ "$skuName" == "7.2" ] || [ "$skuName" == "7.3" ]  ; then
                echo "kernel update is enabled";

	fi

}

disable_kernel_update()
{
	if [ "$skuName" == "6.5" ] || [ "$skuName" == "7.1" ]; then
		cd /etc && sed -i.bak -e '28d' yum.conf
		cd /etc && sed -i '28iexclude=kernel*' yum.conf

	elif [ "$skuName" == "6.6" ] || [ "$skuName" == "7.2" ] || [ "$skuName" == "7.3" ]  ; then
                echo "No kernel to update";

	fi

}

waagent_cleanrpm_master()
{
rpm -q WALinuxAgent | awk '{print $1}'|xargs yum erase -y && \
curl https://bootstrap.pypa.io/ez_setup.py -o - | python && \
git clone https://github.com/Azure/WALinuxAgent.git && \
cd WALinuxAgent && \
python setup.py bdist_rpm && \
cd dist && \
rpm -ivh WALinuxAgent-*.noarch.rpm && \
cd ../ && \
python setup.py install --register-service && \
systemctl start waagent.service && \
systemctl enable waagent.service
}

# Partitions all data disks attached to the VM and creates
# a RAID-0 volume with them.
#
setup_data_disks()
{
    mountPoint="$1"
    createdPartitions=""

    # Loop through and partition disks until not found
    for disk in sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav sdaw sdax sday sdaz sdaaa sdaab ; do
        fdisk -l /dev/$disk || break
        fdisk /dev/$disk << EOF
n
p
1


t
fd
w
EOF
        createdPartitions="$createdPartitions /dev/${disk}1"
    done

    # Create RAID-0 volume
    if [ -n "$createdPartitions" ]; then
        devices=`echo $createdPartitions | wc -w`
        mdadm --create /dev/md10 --level 0 --raid-devices $devices $createdPartitions
        
        mkfs -t ext4 /dev/md10
        if [ "$skuName" == "16.04-LTS" ] ; then
        echo "/dev/md127 $mountPoint ext4 defaults,nofail 0 2" >> /etc/fstab
        else
        echo "/dev/md10 $mountPoint ext4 defaults,nofail 0 2" >> /etc/fstab
        fi
        mount /dev/md10
    fi
}
setup_dynamicdata_disks()
{
    mountPoint="$1"
    createdPartitions=""

    # Loop through and partition disks until not found

if [ "$numberofDisks" == "1" ]
then
   disking=( sdc )
        elif [ "$numberofDisks" == "2" ]; then
        disking=( sdc sdd )
        elif [ "$numberofDisks" == "3" ]; then
        disking=( sdc sdd sde )
        elif [ "$numberofDisks" == "4" ]; then
        disking=( sdc sdd sde sdf )
        elif [ "$numberofDisks" == "5" ]; then
        disking=( sdc sdd sde sdf sdg )
        elif [ "$numberofDisks" == "6" ]; then
        disking=( sdc sdd sde sdf sdg sdh )
        elif [ "$numberofDisks" == "7" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi )
        elif [ "$numberofDisks" == "8" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj )
        elif [ "$numberofDisks" == "9" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk )
        elif [ "$numberofDisks" == "10" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl )
        elif [ "$numberofDisks" == "11" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm )
        elif [ "$numberofDisks" == "12" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn )
        elif [ "$numberofDisks" == "13" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo )
        elif [ "$numberofDisks" == "14" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp )
        elif [ "$numberofDisks" == "15" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq )
        elif [ "$numberofDisks" == "16" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr )
        elif [ "$numberofDisks" == "17" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds )
        elif [ "$numberofDisks" == "18" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt )
        elif [ "$numberofDisks" == "19" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu )
        elif [ "$numberofDisks" == "20" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv )
        elif [ "$numberofDisks" == "21" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw )
        elif [ "$numberofDisks" == "22" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx )
        elif [ "$numberofDisks" == "23" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy )
        elif [ "$numberofDisks" == "24" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz )
        elif [ "$numberofDisks" == "25" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa )
        elif [ "$numberofDisks" == "26" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab )
        elif [ "$numberofDisks" == "27" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac )
        elif [ "$numberofDisks" == "28" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad )
        elif [ "$numberofDisks" == "29" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae )
        elif [ "$numberofDisks" == "30" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf )
        elif [ "$numberofDisks" == "31" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag )
        elif [ "$numberofDisks" == "32" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah )
        elif [ "$numberofDisks" == "33" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai )
        elif [ "$numberofDisks" == "34" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj )
        elif [ "$numberofDisks" == "35" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak )
        elif [ "$numberofDisks" == "36" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal )
        elif [ "$numberofDisks" == "37" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam )
        elif [ "$numberofDisks" == "38" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan )
        elif [ "$numberofDisks" == "39" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao )
        elif [ "$numberofDisks" == "40" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap )
        elif [ "$numberofDisks" == "41" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq )
        elif [ "$numberofDisks" == "42" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar )
        elif [ "$numberofDisks" == "43" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas )
        elif [ "$numberofDisks" == "44" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat )
        elif [ "$numberofDisks" == "45" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau )
        elif [ "$numberofDisks" == "46" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav )
        elif [ "$numberofDisks" == "47" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav sdaw )
        elif [ "$numberofDisks" == "48" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav sdaw sdax )
        elif [ "$numberofDisks" == "49" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav sdaw sdax sday )
        elif [ "$numberofDisks" == "50" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav sdaw sdax sday sdaz )
        elif [ "$numberofDisks" == "51" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav sdaw sdax sday sdaz sdaaa )
        elif [ "$numberofDisks" == "52" ]; then
        disking=( sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr sds sdt sdu sdv sdw sdx sdy sdz sdaa sdab sdac sdad sdae sdaf sdag sdah sdai sdaj sdak sdal sdam sdan sdao sdap sdaq sdar sdas sdat sdau sdav sdaw sdax sday sdaz sdaaa sdaab )
   
fi

printf "%s\n" "${disking[@]}"

for disk in "${disking[@]}"
do
        fdisk -l /dev/$disk || break
        fdisk /dev/$disk << EOF
n
p
1


t
fd
w
EOF
        createdPartitions="$createdPartitions /dev/${disk}1"
done

    # Create RAID-0 volume
    if [ -n "$createdPartitions" ]; then
        devices=`echo $createdPartitions | wc -w`
        mdadm --create /dev/md10 --level 0 --raid-devices $devices $createdPartitions
        mkfs -t ext4 /dev/md10
        echo "/dev/md10 $mountPoint ext4 defaults,nofail 0 2" >> /etc/fstab
        mount /dev/md10
    fi
}


set_time()
{
    mv /etc/localtime /etc/localtime.bak
    #ln -s /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime
    /usr/share/zoneinfo/US/Central /etc/localtime
}


# System Update.
#
system_update()
{
    rpm --rebuilddb
    updatedb
    yum clean all
    yum -y install epel-release
    #yum  -y update --exclude=WALinuxAgent
    #yum  -y update
    #yum -x 'intel-*' -x 'kernel*' -x '*microsoft-*' -x 'msft-*'  -y update --exclude=WALinuxAgent
    if [[ "${HEADNODE_SIZE}" =~ "H" ]] && [[ "${WORKERNODE_SIZE}" =~ "H" ]] && [[ "${HEADNODE_SIZE}" =~ "R" ]] && [[ "${WORKERNODE_SIZE}" =~ "R" ]] && [[ "$skuName" == "7.3" ]] ; then
	    return
    fi
    yum --exclude WALinuxAgent,intel-*,kernel*,kernel-headers*,*microsoft-*,msft-* -y update

    set_time
}

install_docker()
{
if false
then
    wget -qO- "https://pgp.mit.edu/pks/lookup?op=get&search=0xee6d536cf7dc86e2d7d56f59a178ac6c6238f52e" 
    rpm --import "https://pgp.mit.edu/pks/lookup?op=get&search=0xee6d536cf7dc86e2d7d56f59a178ac6c6238f52e"
    yum install -y yum-utils
    yum-config-manager --add-repo https://packages.docker.com/$dockerVer/yum/repo/main/centos/7
    yum install -y docker-engine
 fi
  yum install -y yum-utils
  yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/$dockerVer.repo
  yum makecache fast
  yum -y install docker-ce
    systemctl stop firewalld
    systemctl disable firewalld
    gpasswd -a $userName docker 
    systemctl start docker
    systemctl enable docker
     curl -L "https://github.com/docker/compose/releases/download/$dockerComposeVer/docker-compose-$(uname -s)-$(uname -m)" > /usr/local/bin/docker-compose
    curl -L https://github.com/docker/machine/releases/download/v$dockMVer/docker-machine-`uname -s`-`uname -m` >/usr/local/bin/docker-machine
    chmod +x /usr/local/bin/docker-machine
    chmod +x /usr/local/bin/docker-compose
    export PATH=$PATH:/usr/local/bin/
    systemctl restart docker
 
}
install_docker_ubuntu()
{
	
        # System Update and docker version update
	DEBIAN_FRONTEND=noninteractive apt-mark hold walinuxagent
        DEBIAN_FRONTEND=noninteractive apt-get -y update
         apt-get install -y apt-transport-https ca-certificates curl
	 DEBIAN_FRONTEND=noninteractive apt-get -y update
         DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
	 apt-get install -y linux-image-extra-$(uname -r) linux-image-extra-virtual
         curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
       add-apt-repository \
       "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) \
       stable"
       DEBIAN_FRONTEND=noninteractive apt-get -y update
	 groupadd docker
	 usermod -aG docker $userName
	 apt-get -y install $dockerVer
	 /etc/init.d/apparmor stop 
	 /etc/init.d/apparmor teardown 
	 update-rc.d -f apparmor remove
	 apt-get -y remove apparmor
    curl -L https://github.com/docker/compose/releases/download/$dockerComposeVer/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
    curl -L https://github.com/docker/machine/releases/download/v$dockMVer/docker-machine-`uname -s`-`uname -m` >/usr/local/bin/docker-machine
    chmod +x /usr/local/bin/docker-machine
    chmod +x /usr/local/bin/docker-compose
    export PATH=$PATH:/usr/local/bin/
    systemctl restart docker
}
install_nvdia_ubuntu()
{
service lightdm stop 
wget  http://us.download.nvidia.com/XFree86/Linux-x86_64/$TESLA_DRIVER_LINUX/NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run
apt-get install -y linux-image-virtual
apt-get install -y linux-virtual-lts-xenial
apt-get install -y linux-tools-virtual-lts-xenial linux-cloud-tools-virtual-lts-xenial
apt-get install -y linux-tools-virtual linux-cloud-tools-virtual
DEBIAN_FRONTEND=noninteractive apt-mark hold walinuxagent
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential gcc gcc-multilib dkms g++ make binutils linux-headers-`uname -r` linux-headers-4.4.0-70-generic
chmod +x NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run
./NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run  --silent --dkms
DEBIAN_FRONTEND=noninteractive update-initramfs -u
sleep 120
}
install_azure_cli()
{
    yum install -y nodejs
    yum install -y npm
    npm install -g azure-cli
}

install_docker_apps()
{

    
    docker run -dti --restart=always --name=azure-cli microsoft/azure-cli
    docker run -dti --restart=always --name=azure-cli-python azuresdk/azure-cli-python
}

install_ib()
{
    yum groupinstall -y "Infiniband Support"
    yum install -y infiniband-diags perftest qperf opensm
    chkconfig opensm on
    chkconfig rdma on
}
# Installs individual packages of interest.
#
install_packages()
{
    yum -y install zlib zlib-devel bzip2 bzip2-devel bzip2-libs openssl openssl-devel openssl-libs  nfs-utils rpcbind git libicu libicu-devel make zip unzip mdadm wget gsl bc rpm-build  readline-devel pam-devel libXtst.i686 libXtst.x86_64 make.x86_64 sysstat.x86_64 python-pip automake autoconf\
    binutils.x86_64 compat-libcap1.x86_64 glibc.i686 glibc.x86_64 \
    ksh compat-libstdc++-33 libaio.i686 libaio.x86_64 libaio-devel.i686 libaio-devel.x86_64 \
    libgcc.i686 libgcc.x86_64 libstdc++.i686 libstdc++.x86_64 libstdc++-devel.i686 libstdc++-devel.x86_64 libXi.i686 libXi.x86_64
}

install_packages_ubuntu()
{
DEBIAN_FRONTEND=noninteractive apt-mark hold walinuxagent
DEBIAN_FRONTEND=noninteractive apt-get install -y zlib1g zlib1g-dev  bzip2 libbz2-dev libssl1.0.0  libssl-doc libssl1.0.0-dbg libsslcommon2 libsslcommon2-dev libssl-dev  nfs-common rpcbind git zip libicu55 libicu-dev icu-devtools unzip mdadm wget gsl-bin libgsl2  bc ruby-dev gcc make autoconf bison build-essential libyaml-dev libreadline6-dev libncurses5 libncurses5-dev libffi-dev libgdbm3 libgdbm-dev libpam0g-dev libxtst6 libxtst6-* libxtst-* libxext6 libxext6-* libxext-* git-core libelf-dev asciidoc binutils-dev fakeroot crash kexec-tools makedumpfile kernel-wedge portmap
DEBIAN_FRONTEND=noninteractive apt-get -y build-dep linux
DEBIAN_FRONTEND=noninteractive apt-get -y update
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

DEBIAN_FRONTEND=noninteractive update-initramfs -u
}
# Installs all required packages.
#
install_packages_kernel_headers()
{
	enable_kernel_update
	
	yum -y install icu patch ruby ruby-devel rubygems  gcc gcc-c++ gcc.x86_64 gcc-c++.x86_64 glibc-devel.i686 glibc-devel.x86_64  libtool  libxml2-devel boost-devel openldap-clients nss-pam-ldapd
	
	disable_kernel_update
}
install_pkgs_all()
{
    system_update
     
    yum install -y expect

    install_packages
    
    install_packages_kernel_headers

	if [ "$skuName" == "6.5" ] || [ "$skuName" == "6.6" ] ; then
    		install_azure_cli
	elif [ "$skuName" == "7.2" ] || [ "$skuName" == "7.1" ] || [ "$skuName" == "7.3" ] ; then

    		install_docker

    		install_docker_apps
	fi

	if [[ "${HEADNODE_SIZE}" =~ "H" ]] && [[ "${WORKERNODE_SIZE}" =~ "H" ]] && [[ "${HEADNODE_SIZE}" =~ "R" ]] && [[ "${WORKERNODE_SIZE}" =~ "R" ]] && [[ "$skuName" == "7.3" ]] ; then
		return
	fi

	install_ib
}


# Creates and exports two shares on the master nodes:
#
# /share/home (for HPC user)
# /share/data
#
# These shares are mounted on all worker nodes.
#
setup_shares()
{
    mkdir -p $SHARE_HOME
    mkdir -p $SHARE_DATA

    if is_master; then
        #setup_data_disks $SHARE_DATA
        echo "$SHARE_HOME    *(rw,async)" >> /etc/exports
        echo "$SHARE_DATA    *(rw,async)" >> /etc/exports
	if [ "$skuName" == "16.04-LTS" ] ; then
	         DEBIAN_FRONTEND=noninteractive apt-get -y \
		  -o DPkg::Options::=--force-confdef \
		 -o DPkg::Options::=--force-confold \
    		install nfs-kernel-server
		/etc/init.d/apparmor stop 
		/etc/init.d/apparmor teardown 
		update-rc.d -f apparmor remove
		apt-get -y remove apparmor
                systemctl start rpcbind || echo "Already enabled"
                systemctl start nfs-server || echo "Already enabled"
                systemctl start nfs-kernel-server.service
                systemctl enable rpcbind || echo "Already enabled"
                systemctl enable nfs-server || echo "Already enabled"
                systemctl enable nfs-kernel-server.service
        else
	        
                systemctl start rpcbind || echo "Already enabled"
                systemctl start nfs-server || echo "Already enabled"
                systemctl enable rpcbind || echo "Already enabled"
                systemctl enable nfs-server || echo "Already enabled"
         fi
        setup_dynamicdata_disks $SHARE_DATA
    else

	        echo "$MASTER_HOSTNAME:$SHARE_DATA $SHARE_DATA    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
	        echo "$MASTER_HOSTNAME:$SHARE_HOME $SHARE_HOME    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
	        mount -a
	        mount | grep "^$MASTER_HOSTNAME:$SHARE_HOME"
	        mount | grep "^$MASTER_HOSTNAME:$SHARE_DATA"

    fi
}


# Adds a common HPC user to the node and configures public key SSh auth.
# The HPC user has a shared home directory (NFS share on master) and access
# to the data share.
#
setup_hpc_user()
{

	if [ "$skuName" == "16.04-LTS" ] ; then
		/etc/init.d/apparmor stop 
		/etc/init.d/apparmor teardown 
		update-rc.d -f apparmor remove
		apt-get -y remove apparmor

	elif [ "$skuName" == "6.5" ] || [ "$skuName" == "6.6" ] || [ "$skuName" == "7.2" ] || [ "$skuName" == "7.1" ] || [ "$skuName" == "7.3" ] ; then
		    sed -i 's/enforcing/disabled/g' /etc/selinux/config
		    setenforce permissive

	fi

    
    groupadd -g $HPC_GID $HPC_GROUP

    # Don't require password for HPC user sudo
    echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    # Disable tty requirement for sudo
    sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

    if is_master; then
    
        useradd -c "HPC User" -g $HPC_GROUP -m -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER

        mkdir -p $SHARE_HOME/$HPC_USER/.ssh
        
        # Configure public key auth for the HPC user
        ssh-keygen -t rsa -f $SHARE_HOME/$HPC_USER/.ssh/id_rsa -q -P ""
        cat $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub > $SHARE_HOME/$HPC_USER/.ssh/authorized_keys

        echo "Host *" > $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    StrictHostKeyChecking no" >> $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    UserKnownHostsFile /dev/null" >> $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    PasswordAuthentication no" >> $SHARE_HOME/$HPC_USER/.ssh/config

        # Fix .ssh folder ownership
        chown -R $HPC_USER:$HPC_GROUP $SHARE_HOME/$HPC_USER

        # Fix permissions
        chmod 700 $SHARE_HOME/$HPC_USER/.ssh
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/config
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/authorized_keys
        chmod 600 $SHARE_HOME/$HPC_USER/.ssh/id_rsa
        chmod 644 $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub
        
        # Give hpc user access to data share
        chown -R $HPC_USER:$HPC_GROUP $SHARE_DATA
        
        
    else
        useradd -c "HPC User" -g $HPC_GROUP -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER
    fi
}

# Sets all common environment variables and system parameters.
#
setup_env()
{
    # Set unlimited mem lock
    echo "$HPC_USER hard memlock unlimited" >> /etc/security/limits.conf
    echo "$HPC_USER soft memlock unlimited" >> /etc/security/limits.conf

    # Intel MPI config for IB
    echo "# IB Config for MPI" > /etc/profile.d/mpi.sh
    echo "export I_MPI_FABRICS=shm:dapl" >> /etc/profile.d/mpi.sh
    echo "export I_MPI_DAPL_PROVIDER=ofa-v2-ib0" >> /etc/profile.d/mpi.sh
    echo "export I_MPI_DYNAMIC_CONNECTION=0" >> /etc/profile.d/mpi.sh
    source /opt/intel/compilers_and_libraries/linux/mpi/intel64/bin/mpivars.sh
}


postinstall_centos73ncgpu()
{
wget http://us.download.nvidia.com/XFree86/Linux-x86_64/$TESLA_DRIVER_LINUX/NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run
yum clean all
yum update -y  dkms
yum install -y gcc make binutils gcc-c++ kernel-devel kernel-headers --disableexcludes=all
yum -y upgrade kernel kernel-devel
chmod +x NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run

cat >>~/install_nvidiarun.sh <<EOF
set -e && \
cd /var/lib/waagent/custom-script/download/0 && \
./NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run --silent --dkms --install-libglvnd || true && \
sed -i '$ d' /etc/rc.d/rc.local && \
chmod -x /etc/rc.d/rc.local && \
rm -rf ~/install_nvidiarun.sh
EOF

chmod +x ~/install_nvidiarun.sh
echo -ne "/root/install_nvidiarun.sh" >> /etc/rc.d/rc.local
chmod +x /etc/rc.d/rc.local
}

install_torque()
{
if is_master; then
# Prep packages
# Download the source package
cd /tmp >> /tmp/azure_pbsdeploy.log.$$ 2>&1
wget http://www.adaptivecomputing.com/index.php?wpfb_dl=3170 -O torque.tar.gz >> /tmp/azure_pbsdeploy.log.$$ 2>&1
tar xzvf torque.tar.gz >> /tmp/azure_pbsdeploy.log.$$ 2>&1
cd torque-6.1.0* >> /tmp/azure_pbsdeploy.log.$$ 2>&1

# Build
./configure >> /tmp/azure_pbsdeploy.log.$$ 2>&1
make >> /tmp/azure_pbsdeploy.log.$$ 2>&1
make packages >> /tmp/azure_pbsdeploy.log.$$ 2>&1
make install >> /tmp/azure_pbsdeploy.log.$$ 2>&1

export PATH=/usr/local/bin/:/usr/local/sbin/:$PATH

# Create and start trqauthd
cp contrib/init.d/trqauthd /etc/init.d/ >> /tmp/azure_pbsdeploy.log.$$ 2>&1
chkconfig --add trqauthd >> /tmp/azure_pbsdeploy.log.$$ 2>&1
sh -c "echo /usr/local/lib > /etc/ld.so.conf.d/torque.conf" >> /tmp/azure_pbsdeploy.log.$$ 2>&1
ldconfig >> /tmp/azure_pbsdeploy.log.$$ 2>&1
service trqauthd start >> /tmp/azure_pbsdeploy.log.$$ 2>&1

# Update config
sh -c "echo $MASTER_HOSTNAME > /var/spool/torque/server_name" >> /tmp/azure_pbsdeploy.log.$$ 2>&1

env "PATH=$PATH" sh -c "echo 'y' | ./torque.setup root" >> /tmp/azure_pbsdeploy.log.$$ 2>&1

sh -c "echo $MASTER_HOSTNAME > /var/spool/torque/server_priv/nodes" >> /tmp/azure_pbsdeploy.log.$$ 2>&1

# Start pbs_server
cp contrib/init.d/pbs_server /etc/init.d >> /tmp/azure_pbsdeploy.log.$$ 2>&1
chkconfig --add pbs_server >> /tmp/azure_pbsdeploy.log.$$ 2>&1
service pbs_server restart >> /tmp/azure_pbsdeploy.log.$$ 2>&1

# Start pbs_mom
cp contrib/init.d/pbs_mom /etc/init.d >> /tmp/azure_pbsdeploy.log.$$ 2>&1
chkconfig --add pbs_mom >> /tmp/azure_pbsdeploy.log.$$ 2>&1
service pbs_mom start >> /tmp/azure_pbsdeploy.log.$$ 2>&1

# Start pbs_sched
env "PATH=$PATH" pbs_sched >> /tmp/azure_pbsdeploy.log.$$ 2>&1
# Push packages to compute nodes
c=0
rm -rf /tmp/hosts
echo "$MASTER_HOSTNAME" > /tmp/host
while [ $c -lt $WORKER_COUNT ]
do
        printf "\n$WORKER_HOSTNAME_PREFIX$c">> /tmp/host
        workerhost=$WORKER_HOSTNAME_PREFIX$c     
        service pbs_mom stop
        ####Keeping the following three lines for computenode remote ssh script execution but this won't work as compnodes are not created yet####
        service pbs_mom start
        echo $workerhost >> /var/spool/torque/server_priv/nodes
         echo $workerhost
        (( c++ ))
done
sed '2d' /tmp/host > /tmp/hosts
rm -rf /tmp/host


# Restart pbs_server
service pbs_server restart >> /tmp/azure_pbsdeploy.log.$$ 2>&1

cp /var/spool/torque/server_priv/nodes  $SHARE_HOME/$HPC_USER/machines.LINUX
chown $HPC_USER:$HPC_USER $SHARE_HOME/$HPC_USER/machines.LINUX
service pbs_mom start
else

        su -c "scp $HPC_USER@$MASTER_HOSTNAME:/tmp/torque-6.1.0*/torque-package-mom-linux-x86_64.sh /tmp" $HPC_USER	
	su -c "sudo /tmp/torque-package-mom-linux-x86_64.sh --install" $HPC_USER	
        su -c "sudo /usr/local/sbin/pbs_mom" $HPC_USER
        su -c "ssh $MASTER_HOSTNAME 'sudo service pbs_server restart'" $HPC_USER
fi
}
install_pbspro()
{
yum install -y gcc make rpm-build libtool hwloc-devel \
      libX11-devel libXt-devel libedit-devel libical-devel \
      ncurses-devel perl postgresql-devel python-devel tcl-devel \
      tk-devel swig expat-devel openssl-devel libXext libXft \
      autoconf automake \
      expat libedit postgresql-server python \
      sendmail sudo tcl tk libical --setopt=protected_multilib=false

if is_master; then
# Prep packages
# Download the source package
cd /tmp >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
wget -qO- -O tmp.zip https://github.com/PBSPro/pbspro/archive/master.zip >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
unzip tmp.zip >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
rm -rf tmp.zip >> /tmp/azure_pbsprodeploy.log.$$ 2>&1

# Build
cd pbspro-master >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
./autogen.sh >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
./configure --prefix=/opt/pbs >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
make  >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
make install >> /tmp/azure_pbsprodeploy.log.$$ 2>&1

/opt/pbs/libexec/pbs_postinstall >> /tmp/azure_pbsprodeploy.log.$$ 2>&1

chmod 4755 /opt/pbs/sbin/pbs_iff /opt/pbs/sbin/pbs_rcp >> /tmp/azure_pbsprodeploy.log.$$ 2>&1

 . /etc/profile.d/pbs.sh >> /tmp/azure_pbsprodeploy.log.$$ 2>&1
 
 /etc/init.d/pbs start >> /tmp/azure_pbsprodeploy.log.$$ 2>&1

# Push packages to compute nodes
c=0
rm -rf /tmp/hosts
echo "$MASTER_HOSTNAME" > /tmp/host
while [ $c -lt $WORKER_COUNT ]
do
        printf "\n$WORKER_HOSTNAME_PREFIX$c">> /tmp/host
        workerhost=$WORKER_HOSTNAME_PREFIX$c     
        echo "$workerhost np=1" >> /var/spool/pbs/server_priv/nodes
        echo $workerhost
        qmgr -c "create node $workerhost"
        qmgr -c "s s job_history_enable = true"
        qmgr -c "s s job_history_duration = 336:0:0"
        qmgr -c "s s managers = $HPC_USER@*"
        (( c++ ))
done
# MASTER also has pbs_mom started
echo "$MASTER_HOSTNAME np=1" >> /var/spool/pbs/server_priv/nodes
qmgr -c "create node $MASTER_HOSTNAME"
su -c "cd /etc && sudo sed -i.bak -e '5d' pbs.conf" $HPC_USER
su -c "cd /etc && sudo sed -i '5iPBS_START_MOM=1' pbs.conf" $HPC_USER

sed '2d' /tmp/host > /tmp/hosts
rm -rf /tmp/host


# restart pbs_server
/etc/init.d/pbs restart >> /tmp/azure_pbsprodeploy.log.$$ 2>&1

cp /var/spool/pbs/server_priv/nodes  $SHARE_HOME/$HPC_USER/machines.LINUX

chown $HPC_USER:$HPC_USER $SHARE_HOME/$HPC_USER/machines.LINUX
/etc/init.d/pbs start
else
        su -c "scp -r $HPC_USER@$MASTER_HOSTNAME:/tmp/pbspro-master/ /tmp" $HPC_USER	
	su -c "cd /tmp/pbspro-master/ && sudo ./autogen.sh" $HPC_USER	
        su -c "cd /tmp/pbspro-master/ && sudo ./configure --prefix=/opt/pbs" $HPC_USER
        su -c "cd /tmp/pbspro-master/ && sudo make" $HPC_USER
        su -c "cd /tmp/pbspro-master/ && sudo make install" $HPC_USER
        su -c "sudo /opt/pbs/libexec/pbs_postinstall" $HPC_USER
        su -c "sudo chmod 4755 /opt/pbs/sbin/pbs_iff /opt/pbs/sbin/pbs_rcp" $HPC_USER
        su -c "sudo /etc/init.d/pbs start" $HPC_USER	
        su -c "cd /etc && sudo sed -i.bak -e '5d' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i '5iPBS_START_MOM=1' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i.bak -e '2d' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i '2iPBS_START_SERVER=0' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i.bak -e '3d' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i '3iPBS_START_SCHED=0' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i.bak -e '4d' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i '4iPBS_START_COMM=0' pbs.conf" $HPC_USER
	su -c "cd /etc && sudo sed -i.bak -e '1d' pbs.conf" $HPC_USER
        su -c "cd /etc && sudo sed -i "1iPBS_SERVER=$MASTER_HOSTNAME" pbs.conf" $HPC_USER
	su -c "sudo /etc/init.d/pbs restart" $HPC_USER
        su -c "ssh $MASTER_HOSTNAME 'sudo /etc/init.d/pbs restart'" $HPC_USER
fi
}

install_cuda8061_ubuntu1604()
{
DEBIAN_FRONTEND=noninteractive apt-mark hold walinuxagent
export CUDA_DOWNLOAD_SUM=1f4dffe1f79061827c807e0266568731 && export CUDA_PKG_VERSION=8-0 && curl -o cuda-repo.deb -fsSL http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_$CUDA_VER-1_amd64.deb && \
    echo "$CUDA_DOWNLOAD_SUM  cuda-repo.deb" | md5sum -c --strict - && \
    dpkg -i cuda-repo.deb && \
    rm cuda-repo.deb && \
    apt-get update -y && apt-get install -y cuda && \
    apt-get install -y nvidia-cuda-toolkit && \
export LIBRARY_PATH=/usr/local/cuda-8.0/lib64/:${LIBRARY_PATH}  && export LIBRARY_PATH=/usr/local/cuda-8.0/lib64/stubs:${LIBRARY_PATH} && \
export PATH=/usr/local/cuda-8.0/bin:${PATH}
 if is_master; then
#/usr/local/cuda-8.0/bin/./cuda-install-samples-8.0.sh $SHARE_DATA
su -c "/usr/local/cuda-8.0/bin/./cuda-install-samples-8.0.sh $SHARE_DATA" $HPC_USER
else
echo "already installed on share"
fi
}
install_cudann5()
{
    export CUDNN_DOWNLOAD_SUM=a87cb2df2e5e7cc0a05e266734e679ee1a2fadad6f06af82a76ed81a23b102c8 && curl -fsSL http://developer.download.nvidia.com/compute/redist/cudnn/v5.1/cudnn-8.0-linux-x64-v5.1.tgz -O && \
    echo "$CUDNN_DOWNLOAD_SUM  cudnn-8.0-linux-x64-v5.1.tgz" | sha256sum -c --strict - && \
    tar -xzf cudnn-8.0-linux-x64-v5.1.tgz -C /usr/local && \
    rm cudnn-8.0-linux-x64-v5.1.tgz && \
    ldconfig
}


installomsagent()
{
docker run --privileged -d -v /var/run/docker.sock:/var/run/docker.sock -v /var/log:/var/log -e WSID=$omsworkspaceid -e KEY=$omsworkspacekey -p 127.0.0.1:25225:25225 --name="omsagent" -h=`hostname` --restart=always microsoft/oms
}

install_cuda8centos()
{
wget http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-repo-rhel7-$CUDA_VER-1.x86_64.rpm
rpm -i cuda-repo-rhel7-$CUDA_VER-1.x86_64.rpm
yum clean all
yum install -y cuda
}


postinstall_centos73nvgpu()
{ 
yum groupinstall -y 'KDE' 'X Window System' 'Fonts'
#yum install -y xinetd vnc-ltsp-config kde-workspace gdm
yum install -y vnc-ltsp-config kde-workspace gdm
ln -sf /lib/systemd/system/graphical.target /etc/systemd/system/default.target
systemctl isolate graphical.target
yum clean all
#yum update -y kernel\* selinux-policy\* dkms
yum update -y  dkms
yum install -y gcc make binutils gcc-c++ kernel-devel kernel-headers

grub2-mkconfig -o /boot/grub2/grub.cfg
cd /etc/default && sed -i.bak -e '6d' grub
cd /etc/default && sed -i '6iGRUB_CMDLINE_LINUX="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 net.ifnames=0 rdblacklist=nouveau nouveau.modeset=0"' grub
yum install -y  xorg-x11-drv*
yum erase -y xorg-x11-drv-nouveau
echo 'blacklist nouveau' | tee -a /etc/modprobe.d/blacklist.conf
echo 'options nouveau modeset=0' | tee -a  /etc/modprobe.d/blacklist-nouveau.conf
echo 'alias nouveau off' | tee -a  /etc/modprobe.d/blacklist-nouveau.conf
echo options nouveau modeset=0 | tee -a /etc/modprobe.d/nouveau-kms.conf
rmmod nouveau
dracut --force
#wget https://tdcm16sg112leo8193ls102.blob.core.windows.net/tdcm16sg112leo8193ls102/lis-rpms-4.1.3.tar.gz
#tar -zxvf lis-rpms-4.1.3.tar.gz
wget https://tdcm16sg112leo8193ls102.blob.core.windows.net/tdcm16sg112leo8193ls102/azurenvidia42/NVIDIA-Linux-x86_64-367.92-grid.run
chmod +x NVIDIA-Linux-x86_64-367.92-grid.run
./NVIDIA-Linux-x86_64-367.92-grid.run --silent --dkms --install-libglvnd
dracut --force
#git clone https://github.com/LIS/lis-next.git && cd lis-next/hv-rhel7.x/hv/
#./rhel7-hv-driver-install
#systemctl stop waagent
#systemctl disable waagent
#chmod +x /etc/rc.d/rc.local
#echo "sleep 240" >> /etc/rc.d/rc.local && echo "systemctl enable waagent" >> /etc/rc.d/rc.local && echo "systemctl start waagent" >> /etc/rc.d/rc.local
 # mv /usr/lib64/xorg/modules/extensions/libglx.so /usr/lib64/xorg/modules/extensions/libglx.so.xorg
 #ln -s /usr/lib64/xorg/modules/extensions/libglx.so.367.64 /usr/lib64/xorg/modules/extensions/libglx.so
 # ln -s /usr/lib64/xorg/modules/extensions/libglx.so.367.64 /usr/lib64/xorg/modules/extensions/libglx.so.xorg
 #reboot
}


ubuntunvidiadesktop()
{
apt-get update -y
apt-get install -y linux-image-virtual
apt-get install -y linux-virtual-lts-xenial
apt-get install -y linux-tools-virtual-lts-xenial linux-cloud-tools-virtual-lts-xenial
apt-get install -y linux-tools-virtual linux-cloud-tools-virtual
apt-get install -y --no-install-recommends  ubuntu-desktop gnome-panel gnome-settings-daemon metacity nautilus gnome-terminal
DEBIAN_FRONTEND=noninteractive update-initramfs -u
grub-mkconfig -o /boot/grub/grub.cfg
cd /etc/default && sed -i.bak -e '11d' grub
cd /etc/default && sed -i '11iGRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0 earlyprintk=ttyS0 rootdelay=300 rdblacklist=nouveau nouveau.modeset=0"' grub
update-grub
echo 'blacklist nouveau' | tee -a /etc/modprobe.d/blacklist.conf
echo 'options nouveau modeset=0' | tee -a  /etc/modprobe.d/blacklist-nouveau.conf
echo 'alias nouveau off' | tee -a  /etc/modprobe.d/blacklist-nouveau.conf
service lightdm stop 
#service lightdm disable placeholder
echo options nouveau modeset=0 | tee -a /etc/modprobe.d/nouveau-kms.conf
rmmod nouveau
#DEBIAN_FRONTEND=noninteractive update-initramfs -u
#wget https://tdcm16sg112leo8193ls102.blob.core.windows.net/tdcm16sg112leo8193ls102/NVIDIA-Linux-x86_64-367.64-grid.run
#wget http://us.download.nvidia.com/XFree86/Linux-x86_64/375.39/NVIDIA-Linux-x86_64-375.39.run&lang=us&type=Tesla
#wget https://tdcm16sg112leo8193ls102.blob.core.windows.net/tdcm16sg112leo8193ls102/NVIDIA-Linux-x86_64-367.92-grid.run
wget https://tdcm16sg112leo8193ls102.blob.core.windows.net/tdcm16sg112leo8193ls102/azurenvidia42/NVIDIA-Linux-x86_64-367.92-grid.run
chmod +x NVIDIA-Linux-x86_64-367.92-grid.run
DEBIAN_FRONTEND=noninteractive apt-mark hold walinuxagent
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential gcc gcc-multilib dkms g++ make binutils linux-headers-`uname -r` linux-headers-4.4.0-70-generic
DEBIAN_FRONTEND=noninteractive ./NVIDIA-Linux-x86_64-367.92-grid.run  --silent --dkms --run-nvidia-xconfig
#DEBIAN_FRONTEND=noninteractive update-initramfs -u
##Options for PCOIP- commented now##
#echo 'IgnoreSP=TRUE' | tee -a /etc/nvidia/gridd.conf
#echo 'FeatureType=2' | tee -a /etc/nvidia/gridd.conf
systemctl enable nvidia-gridd
systemctl restart nvidia-gridd

apt-key adv --keyserver pool.sks-keyservers.net --recv-key 67D7ADA8
wget -O /etc/apt/sources.list.d/pcoip.list https://downloads.teradici.com/ubuntu/pcoip-beta.repo
apt-get update -y
apt-get install -y pcoip-agent-graphics
#manual registration
#pcoip-register-host --registration-code=xx
#systemctl enable pcoip
}


#########################
### Place holder for common GPU/HPC Sku operations on both master and computes ###

cat <<EOT >> /etc/profile
if [ "\$USER" = "$HPC_USER" ]; then
    if [ $SHELL = "/bin/ksh" ]; then
        ulimit -p 16384
        ulimit -n 65536
    else
        ulimit -s unlimited
    fi
fi
EOT


echo "$HPC_USER               hard    memlock         unlimited" >> /etc/security/limits.conf
echo "$HPC_USER               soft    memlock         unlimited" >> /etc/security/limits.conf

install_saltsaltstack_centos()
{

if is_master; then
# Install full stack
enable_kernel_update
yum --enablerepo=epel-testing install -y salt-master && yum --enablerepo=epel-testing install -y salt-minion && yum --enablerepo=epel-testing install -y salt-ssh && yum --enablerepo=epel-testing install -y salt-syndic && yum --enablerepo=epel-testing install -y salt-cloud
disable_kernel_update
systemctl enable salt-master.service
systemctl start salt-master.service

# Now for the minions
else
        enable_kernel_update
        su -c "sudo yum --enablerepo=epel-testing install -y salt-minion && yum --enablerepo=epel-testing install -y salt-ssh" $HPC_USER
        disable_kernel_update
	sed -i "s/#master: salt/master: $MASTER_HOSTNAME/" /etc/salt/minion
	su -c "sudo systemctl enable salt-minion.service" $HPC_USER
	su -c "sudo systemctl start salt-minion.service" $HPC_USER
        su -c "sudo systemctl restart salt-minion.service" $HPC_USER
	workerhostintip="$(hostname --fqdn)"
	su -c "ssh $MASTER_HOSTNAME "sudo salt-key -a $workerhostintip -y"" $HPC_USER
	su -c "sudo systemctl restart salt-minion.service" $HPC_USER
fi
}

install_saltsaltstack_ubuntu()
{

if is_master; then
# Install full stack
wget -O - https://repo.saltstack.com/apt/ubuntu/16.04/amd64/latest/SALTSTACK-GPG-KEY.pub | sudo apt-key add -
echo "deb http://repo.saltstack.com/apt/ubuntu/16.04/amd64/latest xenial main" | sudo tee /etc/apt/sources.list.d/saltstack.list
DEBIAN_FRONTEND=noninteractive apt-get update -y
apt-get install -y salt-master
apt-get install -y  salt-minion
apt-get install -y salt-ssh
apt-get install -y salt-syndic
apt-get install -y  salt-cloud
apt-get install -y salt-api
systemctl enable salt-master.service
systemctl start salt-master.service

# Now for the minions
else

        su -c "sudo apt-get install -y salt-minion && apt-get install -y salt-ssh" $HPC_USER
	sed -i "s/#master: salt/master: $MASTER_HOSTNAME/" /etc/salt/minion
	su -c "sudo systemctl enable salt-minion.service" $HPC_USER
	su -c "sudo systemctl start salt-minion.service" $HPC_USER	
	workerhostintip="$(hostname --fqdn)"
	su -c "ssh $MASTER_HOSTNAME 'sudo salt-key -a $workerhostintip -y'" $HPC_USER
	su -c "sudo systemctl restart salt-minion.service" $HPC_USER
fi
}


ubuntu_nvidia-docker()
{
wget -P /tmp https://github.com/NVIDIA/nvidia-docker/releases/download/v$nvidiadockerbinver/nvidia-docker_$nvidiadockerbinver-1_amd64.deb
dpkg -i /tmp/nvidia-docker*.deb && rm /tmp/nvidia-docker*.deb
#systemctl enable nvidia-docker
#systemctl start nvidia-docker
}

centos_nvidia-docker()
{
wget -P /tmp https://github.com/NVIDIA/nvidia-docker/releases/download/v$nvidiadockerbinver/nvidia-docker-$nvidiadockerbinver-1.x86_64.rpm
rpm -ivh /tmp/nvidia-docker*.rpm && rm /tmp/nvidia-docker*.rpm
#systemctl enable nvidia-docker
#systemctl start nvidia-docker
}

install_cudalatest_centos()
{
export NVIDIA_GPGKEY_SUM=d1be581509378368edeec8c1eb2958702feedf3bc3d17011adbf24efacce4ab5 && \
    curl -fsSL http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/7fa2af80.pub | sed '/^Version/d' > /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA && \
    echo "$NVIDIA_GPGKEY_SUM  /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA" | sha256sum -c --strict -

cp cuda.repo /etc/yum.repos.d/cuda.repo

yum install -y \
        cuda-nvrtc-8-0-$CUDA_VERSION-1 \
        cuda-nvgraph-8-0-$CUDA_VERSION-1 \
        cuda-cusolver-8-0-$CUDA_VERSION-1 \
        cuda-cublas-8-0-$CUDA_VERSION-1 \
        cuda-cufft-8-0-$CUDA_VERSION-1 \
        cuda-curand-8-0-$CUDA_VERSION-1 \
        cuda-cusparse-8-0-$CUDA_VERSION-1 \
        cuda-npp-8-0-$CUDA_VERSION-1 \
        cuda-cudart-8-0-$CUDA_VERSION-1 && \
    ln -s cuda-8.0 /usr/local/cuda && \
    rm -rf /var/cache/yum/*

echo "/usr/local/cuda/lib64" >> /etc/ld.so.conf.d/cuda.conf && \
    ldconfig

echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf && \
echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf

export PATH /usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
export LD_LIBRARY_PATH /usr/local/nvidia/lib:/usr/local/nvidia/lib64
}

install_cudalatest_centos()
{
export NVIDIA_GPGKEY_SUM=d1be581509378368edeec8c1eb2958702feedf3bc3d17011adbf24efacce4ab5 && \
    curl -fsSL http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/7fa2af80.pub | sed '/^Version/d' > /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA && \
    echo "$NVIDIA_GPGKEY_SUM  /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA" | sha256sum -c --strict -

cp cuda.repo /etc/yum.repos.d/cuda.repo

yum install -y \
        cuda-nvrtc-$CUDA_VERSION-1 \
        cuda-nvgraph-$CUDA_VERSION-1 \
        cuda-cusolver-$CUDA_VERSION-1 \
        cuda-cublas-$CUDA_VERSION-1 \
        cuda-cufft-$CUDA_VERSION-1 \
        cuda-curand-$CUDA_VERSION-1 \
        cuda-cusparse-$CUDA_VERSION-1 \
        cuda-npp-$CUDA_VERSION-1 \
        cuda-cudart-$CUDA_VERSION-1 && \
    ln -s cuda-8.0 /usr/local/cuda && \
    rm -rf /var/cache/yum/*

echo "/usr/local/cuda/lib64" >> /etc/ld.so.conf.d/cuda.conf && \
    ldconfig

echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf && \
echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf

export PATH /usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
export LD_LIBRARY_PATH /usr/local/nvidia/lib:/usr/local/nvidia/lib64
}

install_cudalatest_ubuntu()
{
export NVIDIA_GPGKEY_SUM=d1be581509378368edeec8c1eb2958702feedf3bc3d17011adbf24efacce4ab5 && \
    export NVIDIA_GPGKEY_FPR=ae09fe4bbd223a84b2ccfce3f60f4b3d7fa2af80 && \
    apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub && \
    apt-key adv --export --no-emit-version -a $NVIDIA_GPGKEY_FPR | tail -n +5 > cudasign.pub && \
    echo "$NVIDIA_GPGKEY_SUM  cudasign.pub" | sha256sum -c --strict - && rm cudasign.pub && \
    echo "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64 /" > /etc/apt/sources.list.d/cuda.list

apt-get update && apt-get install -y --no-install-recommends \
        cuda-nvrtc-$CUDA_VERSION-1 \
        cuda-nvgraph-$CUDA_VERSION-1 \
        cuda-cusolver-$CUDA_VERSION-1 \
        cuda-cublas-$CUDA_VERSION-1 \
        cuda-cufft-$CUDA_VERSION-1 \
        cuda-curand-$CUDA_VERSION-1 \
        cuda-cusparse-$CUDA_VERSION-1 \
        cuda-npp-$CUDA_VERSION-1 \
        cuda-cudart-$CUDA_VERSION-1 && \
    ln -s cuda-8.0 /usr/local/cuda && \
    rm -rf /var/lib/apt/lists/*

    echo "/usr/local/cuda/lib64" >> /etc/ld.so.conf.d/cuda.conf && \
    ldconfig

    echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf && \
    echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf

export PATH /usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
export LD_LIBRARY_PATH /usr/local/nvidia/lib:/usr/local/nvidia/lib64
}


postinstall_centos73nc24Rgpu()
{
# Download latest NVIDIA TESLA Driver
wget http://us.download.nvidia.com/XFree86/Linux-x86_64/$TESLA_DRIVER_LINUX/NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run
yum clean all
yum update -y  dkms
yum install -y gcc make binutils gcc-c++ kernel-devel kernel-headers --disableexcludes=all

# Update kernel and kernel-devel
yum -y upgrade kernel kernel-devel
chmod +x NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run

# Create Script for rc.local to be invoked on reboot
cat >>~/install_nvidiarun.sh <<EOF
set -e && \
cd /var/lib/waagent/custom-script/download/0 && \
./NVIDIA-Linux-x86_64-$TESLA_DRIVER_LINUX.run --silent --dkms --install-libglvnd || true && \
git clone https://github.com/LIS/lis-next.git && \
 cd lis-next/hv-rhel7.x/hv/ && \
./rhel7-hv-driver-uninstall && \
./rhel7-hv-driver-install && \
cd /var/lib/waagent/custom-script/download/0 && \
rpm -q WALinuxAgent | awk '{print $1}'|xargs yum erase -y && \
curl https://bootstrap.pypa.io/ez_setup.py -o - | python && \
git clone https://github.com/Azure/WALinuxAgent.git && \
cd WALinuxAgent && \
python setup.py bdist_rpm && \
cd dist && \
rpm -ivh WALinuxAgent-*.noarch.rpm && \
cd ../ && \
python setup.py install --register-service && \
yum install -y kmod-microsoft-hyper-v microsoft-hyper-v microsoft-hyper-v-debuginfo msft-rdma-drivers && \
sed -i 's/^\#\s*OS.EnableRDMA=.*/OS.EnableRDMA=y/' /etc/waagent.conf  && \
systemctl enable hv_kvp_daemon.service && \
waagent -register-service && \
systemctl start waagent.service && \
systemctl enable waagent.service && \

sed -i '$ d' /etc/rc.d/rc.local && \
chmod -x /etc/rc.d/rc.local && \
rm -rf ~/install_nvidiarun.sh && \
( sleep 60 ; reboot ) &
EOF

chmod +x ~/install_nvidiarun.sh
echo -ne "/root/install_nvidiarun.sh" >> /etc/rc.d/rc.local
chmod +x /etc/rc.d/rc.local
}


#########################
	if [ "$skuName" == "16.04-LTS" ] ; then
		install_packages_ubuntu
		DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common
		setup_shares
		setup_hpc_user
                install_docker_ubuntu
                install_docker_apps
		usermod -aG docker $HPC_USER
		 if [ "$SALTSTACKBOOLEAN" == "Yes" ] ; then
		    install_saltsaltstack_ubuntu
		 fi
		if [[ "${HEADNODE_SIZE}" =~ "NC" ]] && [[ "${WORKERNODE_SIZE}" =~ "NC" ]] && [[ "${HEADNODE_SIZE}" =~ "R" ]] && [[ "${WORKERNODE_SIZE}" =~ "R" ]];then
		    echo "this is a NC with RDMA"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
                install_nvdia_ubuntu
                #install_cudann5
                install_cuda8061_ubuntu1604
		#install_cudalatest_ubuntu
		ubuntu_nvidia-docker
		elif [[ "${HEADNODE_SIZE}" =~ "H" ]] && [[ "${WORKERNODE_SIZE}" =~ "H" ]] && [[ "${HEADNODE_SIZE}" =~ "R" ]] && [[ "${WORKERNODE_SIZE}" =~ "R" ]];then
		    echo "this is a H with RDMA"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi		    
		elif [[ "${HEADNODE_SIZE}" =~ "H" ]] && [[ "${WORKERNODE_SIZE}" =~ "H" ]];then
		        echo "this is a H"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi		        
		elif [[ "${HEADNODE_SIZE}" =~ "NV" ]] && [[ "${WORKERNODE_SIZE}" =~ "NV" ]];then
		        echo "this is a NV"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
		 ubuntunvidiadesktop
		 ( sleep 15 ; reboot ) &
		elif [[ "${HEADNODE_SIZE}" =~ "NC" ]] && [[ "${WORKERNODE_SIZE}" =~ "NC" ]];then
		        echo "this is a NC"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi	
                install_nvdia_ubuntu
                #install_cudann5
                install_cuda8061_ubuntu1604
		#install_cudalatest_ubuntu
		ubuntu_nvidia-docker
		 ( sleep 15 ; reboot ) &
		fi
                
	elif [ "$skuName" == "6.5" ] || [ "$skuName" == "6.6" ] || [ "$skuName" == "7.2" ] || [ "$skuName" == "7.1" ] || [ "$skuName" == "7.3" ] || [ "$skuName" == "42.2" ] || [ "$skuName" == "12-SP2" ] ; then
		install_pkgs_all
		setup_shares
		setup_hpc_user
		gpasswd -a $HPC_USER docker
		setup_env

		    if [ "$SALTSTACKBOOLEAN" == "Yes" ] ; then
		    install_saltsaltstack_centos
		    fi
		if [[ "${HEADNODE_SIZE}" =~ "NC" ]] && [[ "${WORKERNODE_SIZE}" =~ "NC" ]] && [[ "${HEADNODE_SIZE}" =~ "R" ]] && [[ "${WORKERNODE_SIZE}" =~ "R" ]];then
		    echo "this is a NC with RDMA"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
		    enable_kernel_update
		    #postinstall_centos73ncgpu
		    postinstall_centos73nc24Rgpu
		    install_cuda8centos
		    #install_cudann5
		    #install_cudalatest_centos
		    centos_nvidia-docker
		    disable_kernel_update
		    ( sleep 45 ; reboot ) &
		elif [[ "${HEADNODE_SIZE}" =~ "H" ]] && [[ "${WORKERNODE_SIZE}" =~ "H" ]] && [[ "${HEADNODE_SIZE}" =~ "R" ]] && [[ "${WORKERNODE_SIZE}" =~ "R" ]];then
		    echo "this is a H with RDMA"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
		    
	            if [ "$TORQUEORPBS" == "Torque" ] ; then
		    install_torque
		    elif [ "$TORQUEORPBS" == "pbspro" ] ; then
		    enable_kernel_update
		    install_pbspro
		    disable_kernel_update
		    else
		    echo "nothing to install"
		    fi
		    if [ "$skuName" == "7.1" ] ; then		    
                    echo 'export PATH=/opt/intel/compilers_and_libraries_2016/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/etc/profile
		    echo 'export PATH=/opt/intel/compilers_and_libraries_2016/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/root/.bash_profile
		    elif [ "$skuName" == "7.3" ] ; then
                    echo 'export PATH=/opt/intel/compilers_and_libraries_2017/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/etc/profile
		    echo 'export PATH=/opt/intel/compilers_and_libraries_2017/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/root/.bash_profile
		    fi 
		elif [[ "${HEADNODE_SIZE}" =~ "H" ]] && [[ "${WORKERNODE_SIZE}" =~ "H" ]];then
		        echo "this is a H"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
		    
	            if [ "$TORQUEORPBS" == "Torque" ] ; then
		    install_torque
		    elif [ "$TORQUEORPBS" == "pbspro" ] ; then
		    enable_kernel_update
		    install_pbspro
		    disable_kernel_update
		    else
		    echo "nothing to install"
		    fi
		    if [ "$skuName" == "7.1" ] ; then		    
                    echo 'export PATH=/opt/intel/compilers_and_libraries_2016/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/etc/profile
		    echo 'export PATH=/opt/intel/compilers_and_libraries_2016/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/root/.bash_profile
		    elif [ "$skuName" == "7.3" ] ; then
                    echo 'export PATH=/opt/intel/compilers_and_libraries_2017/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/etc/profile
		    echo 'export PATH=/opt/intel/compilers_and_libraries_2017/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/root/.bash_profile
		    fi 
		elif [[ "${HEADNODE_SIZE}" =~ "A" ]] && [[ "${WORKERNODE_SIZE}" =~ "A" ]] && [[ "${HEADNODE_SIZE}" =~ "9" ]] && [[ "${WORKERNODE_SIZE}" =~ "9" ]];then
		    echo "this is a A9 with RDMA"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
		    
	            if [ "$TORQUEORPBS" == "Torque" ] ; then
		    install_torque
		    elif [ "$TORQUEORPBS" == "pbspro" ] ; then
		    enable_kernel_update
		    install_pbspro
		    disable_kernel_update
		    else
		    echo "nothing to install"
		    fi
		    if [ "$skuName" == "7.1" ] ; then		    
                    echo 'export PATH=/opt/intel/compilers_and_libraries_2016/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/etc/profile
		    echo 'export PATH=/opt/intel/compilers_and_libraries_2016/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/root/.bash_profile
		    elif [ "$skuName" == "7.3" ] ; then
                    echo 'export PATH=/opt/intel/compilers_and_libraries_2017/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/etc/profile
		    echo 'export PATH=/opt/intel/compilers_and_libraries_2017/linux/mpi/bin64:/usr/local/bin:/usr/local/sbin:$PATH' >>/root/.bash_profile
		    fi 
		   
		elif [[ "${HEADNODE_SIZE}" =~ "NV" ]] && [[ "${WORKERNODE_SIZE}" =~ "NV" ]];then
		        echo "this is a NV"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
                    postinstall_centos73nvgpu;
                    ( sleep 15 ; reboot ) &
		elif [[ "${HEADNODE_SIZE}" =~ "NC" ]] && [[ "${WORKERNODE_SIZE}" =~ "NC" ]];then
		        echo "this is a NC"
		    if [ ! -z "$omsworkspaceid" ]; then
		    sleep 30;
		    installomsagent;
		    fi
		    postinstall_centos73ncgpu;
		    install_cuda8centos;
                    #install_cudann5;
		    #install_cudalatest_centos;
		    centos_nvidia-docker;
		    ( sleep 45 ; reboot ) &
		fi
                		
	fi
