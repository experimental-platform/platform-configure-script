# Experimental Platform Configure Script


## Simple Installation

Three steps:

1. Install [Vagrant](https://www.vagrantup.com/downloads.html) and [Virtualbox](https://www.virtualbox.org/wiki/Downloads)
2. Clone this repository and create the VM
3. Install `experimental-platform`

### Requirements

* at least 1 GByte of free RAM
* roughly 5 GByte of free HD space


### Step 1: Install Vagrant and VirtualBox

### Step 2: Start the VM

    $ git clone https://github.com/orgs/experimental-platform/platform-configure-script.git
    $ cd platform-configure-script
    $ vagrant destroy -f
    ==> default: Forcing shutdown of VM...
    ==> default: Destroying VM and associated drives...
    ==> default: Running cleanup tasks for 'file' provisioner...
    ==> default: Running cleanup tasks for 'shell' provisioner...
    haardt@Vanaheimr:[platform-configure-script] (master *+)$ vagrant up
    Bringing machine 'default' up with 'virtualbox' provider...
    ==> default: Importing base box 'coreos-beta'...
    ==> default: Matching MAC address for NAT networking...
    ==> default: Checking if box 'coreos-beta' is up to date...
    ==> default: Setting the name of the VM: platform-configure-script_default_1438003413095_43927
    ==> default: Clearing any previously set network interfaces...
    ==> default: Available bridged network interfaces:
    1) en0: WLAN (AirPort)
    2) p2p0
    3) awdl0
    ==> default: When choosing an interface, it is usually the one that is
    ==> default: being used to connect to the internet.
        default: Which interface should the network bridge to? 1
    ==> default: Preparing network interfaces based on configuration...
        default: Adapter 1: nat
        default: Adapter 2: bridged
    ==> default: Forwarding ports...
        default: 22 => 2222 (adapter 1)
    ==> default: Running 'pre-boot' VM customizations...
    ==> default: Booting VM...
    ==> default: Waiting for machine to boot. This may take a few minutes...
        default: SSH address: 127.0.0.1:2222
        default: SSH username: core
        default: SSH auth method: private key
        default: Warning: Connection timeout. Retrying...
    ==> default: Machine booted and ready!
    ==> default: Configuring and enabling network interfaces...
    ==> default: Running provisioner: file...
    ==> default: Running provisioner: shell...
        default: Running: inline script

### Step 3: Install experimental platform

    $ vagrant ssh -c "curl https://git.protorz.net/AAL/platform-configure-script/raw/master/platform-configure.sh | sudo CHANNEL=alpha sh"



    $ time /opt/vagrant/bin/vagrant ssh -c "curl https://git.protorz.net/AAL/platform-configure-script/raw/master/platform-configure.sh | sudo CHANNEL=alpha sh"
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed
    100  4596    0  4596    0     0  30485      0 --:--:-- --:--:-- --:--:-- 37672
    alpha: Pulling from experimentalplatform/configure

    cab7c4dcf81b: Pull complete
    [...]
    Connection to 127.0.0.1 closed.

This step will install the software and then reboot the system. Depending oin the network configuration it might not come up on its own, in that case please start it manually with `vagrant up`. A few moments later the experimental platform web interface should be avaliable under [http://paleale.local](paleale.local).