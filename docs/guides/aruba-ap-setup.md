### Operating System Upgrade and Aruba Instant Access Points Configuration Documentation
### Requirements!
- [TFTP Server](https://github.com/team3011/StemLab_Cyber/blob/main/Aruba_APIN0205_Documentation/tftp%20server.md)
- [Aruba IAP Firmware](https://github.com/team3011/StemLab_Cyber/blob/main/Aruba_APIN0205_Documentation/ArubaInstant_Taurus_6.5.4.15_73677)
- Ubuntu Desktop

#### 1. Upgrade OS Command:

During the upgrade process of the operating system (OS) for Aruba Instant Access Points (IAPs), follow these steps:

- **Step 1**: Configure your computer with a static IP (I used 192.168.1.10).
- **Step 2**: Install and connect to AP using screen

  ```
  sudo apt-get install screen
  sudo screen /dev/ttyUSB0 9600
  ```
  
- **Step 3**: Power cycle the AP:
- **Step 4**: As the AP boots, stop autoboot by pressing 'Enter'. You should see:
  ```
  apboot>
  ```
- **Step 5**: Configure network settings in apboot
  Set your TFTP and IP parameters
  ```
  setenv ipaddr 192.168.1.20
  setenv netmask 255.255.255.0
  setenv serverip 192.168.1.10
  ```
  Verify with:
  ```
  printenv
  ```
- **Step 6**: Flash the Instant image
  ```
  upgrade os 0 ArubaInstant_Taurus_6.5.4.15_73677
  upgrade os 1 ArubaInstant_Taurus_6.5.4.15_73677
  ```
  Wait for each to transfer and flash - it can take several minutes.

- **Step 7**: Enabling the AP
  ```
  proginv system ccode CCODE-RW-de6fdb363ff04c13ee261ec04fbb01bdd482d1cd
  invent -w
  factory_reset
  ```
- **Step 8**: Save and reboot
  Once the upgrade is complete:
  ```
  saveenv
  boot
  ```
  This will take a while to reboot
- **Step 9**: Log into AP with admin/admin
- **Step 10**:
  To configure an IAP as the master, if this is not a master AP, skip this step:
  ```
  iap-master
  ```
  To verify the master configuration you must be connected to a DHCP server then power cycle the AP then run the following:
  ```
  show ap-env
  ```
- **Step 11**: Verify Instant Mode enabled if this AP is the master<br>
  After the reboot:<br>
    The AP should broadcast a WiFi SSID like SetMeUp-xx:xx:xx<br>
    You can connect and access the web UI at:<br>
      http://instant.arubanetworks.com<br>
      https://X.X.X.149<br>
    Default login is admin/admin<br>
- **Step 11**: Setup in GUI
  Click on system in the top right, click admin tab, set password.<br>
  
