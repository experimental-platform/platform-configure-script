# Experimental Platform Configure Script


## Install in local VM

Three steps:

1. Install [Vagrant](https://www.vagrantup.com/downloads.html) and [Virtualbox](https://www.virtualbox.org/wiki/Downloads)
2. Clone this repository and create the VM
3. Install `experimental-platform`

### Requirements

* at least 1 GByte of free RAM
* roughly 5 GByte of free HD space


### Step 1: Install Vagrant and VirtualBox

* [Virtualbox](https://www.virtualbox.org/wiki/Downloads)
* [Vagrant](https://www.vagrantup.com/downloads.html)


### Step 2: Start the VM

    $ git clone https://github.com/orgs/experimental-platform/platform-configure-script.git
    $ cd platform-configure-script
    $ vagrant up

### Step 3: Install experimental platform

    $ vagrant ssh -c "curl https://raw.githubusercontent.com/experimental-platform/platform-configure-script/master/platform-configure.sh | sudo CHANNEL=alpha sh"

This step will install the software and then reboot the system. Depending oin the network configuration it might not come up on its own, in that case please start it manually with `vagrant up`. A few moments later the experimental platform web interface should be available under [http://paleale.local](paleale.local).