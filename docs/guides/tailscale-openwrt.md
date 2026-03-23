### Setup OpenWrt to act as a Tailscale exit node with subnet access
### Requirements!
- none

### 1. Flash OpenWRT onto microSD card using balenaEtcher
  after you have flashed the microSD card with openwrt<br>
  insert the microSD card into the rpi and boot<br>  
### 2. connect the rpi to a computer
  using a network cable<br>
  manually set computer to 192.168.1.2/255.255.255.0/192.168.1.1/8.8.8.8<br>
  open browser and go to 192.168.1.1<br>
  username is root/[blank]<br>
  set password
### 3. Setup ALFA usb dongle
  goto Network -> Wireless<br>
  click Scan<br>
  connect to an SSID<br>
  click save and apply<br>
  goto System -> Software<br>
  click update lists<br>
  install kmod-mt76x2u<br>
  reboot<br>
  goto Network -> Wireless<br>
  remove everything associated with the built in nic<br>
  click scan on radio1 and connect to SSID<br>
  click save and apply<br>
  verify connection by pinging openwrt.org
### 4. Extend the disk space
  goto System -> Software<br>
  install fdisk and e2fsprogs<br>
  either ssh or connect directly to openwrt and run:<br>
  ```
  fdisk -l /dev/mmcblk0
  ```
  this will output the beginning and endings of the partitions on the drive.<br>
  you need to look for the Start location for /dev/mmcblk0p2<br>
  for me, that was 147456<br>
  now run:
  ```
  fdisk /dev/mmcblk0
  ```
  once fdisk is up, send to delete partition 2 (this does NOT delete the data):
  ```
  d
  2
  ```
  recreate partition 2 using the start sector from above
  ```
  n
  p
  2
  147456
  <press enter>
  w
  ```
  if prompted to remove the ext4 signature, type no<br>
  power off the rpi<br>
  remove the microSD card and plug it into a Ubuntu machine<br>
  open up a terminal and run:
  ```
  sudo e2fsck -f /dev/sda2
  sudo resize2fs /dev/sda2
  ```
  eject the card and put back into the openwrt rpi and boot<br>
  verify that the disk space extends to the entire size of the microSD card<br>
### 5. Setup bridge
  goto Network -> Interfaces<br>
  click on edit on the lan<br>
  set ip address to 10.42.1.1/24<br>
  click save and apply<br>
  set computer network to dhcp<br>
  open browser and go to 10.42.1.1<br>
  verify connection by pinging openwrt.org on both the router and the computer
### 6. Setup Tailscale
  goto System -> Software<br>
  click update lists<br>
  install tailscale<br>
  ssh in to openwrt<br>
  Install iptables<br>
  ```
  opkg install iptables iptables-mod-tproxy kmod-nf-nat kmod-nf-conntrack
  ```
  Then enable and start the daemon:
  ```
  tailscale up --advertise-routes=10.42.1.0/24 --advertise-exit-node
  ```
  Then make persistent on boot:
  ```
  uci set tailscale.tailscale=service
  uci set tailscale.tailscale.enabled='1'
  uci set tailscale.tailscale.flags='--advertise-routes=10.42.1.0/24 --advertise-exit-node'
  uci commit tailscale
  ```
  restart tailscale
  ```
  /etc/init.d/tailscale restart
  tailscale status
  ```
  update tailscale
  ```
  tailscale update
  ```
