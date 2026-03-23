### Setting up a Whitelist for Aruba Instant Access Points
### Requirements!
- Ubuntu Server on a RPi4 with SSH enabled

#### 1. Setup up FreeRADIUS:

- **Step 1**: Install FreeRadius.
  ```
  sudo apt update
  sudo apt upgrade -y
  sudo apt install freeradius freeradius-utils -y
  ```
  
- **Step 2**: Configure MAC authentication
  1. open users file:
  ```
  sudo nano /etc/freeradius/3.0/users
  ```
  2. Add entries for each device MAC:
  ```
  # Format: MAC as username, password same as MAC (or blank)
  # do NOT include the colons
  AABBCCDDEEFF   Cleartext-Password := "AABBCCDDEEFF"
  ```
  3. Save the file.
  
- **Step 3**: Configure Aruba Instant VC as RADIUS client:
  1. open clients.conf
  ```
  sudo nano /etc/freeradius/3.0/clients.conf
  ```
  2. Add the Aruba IC as a client
  ```
  client ArubaVC {
    ipaddr = 172.16.67.6       # Replace with your VC IP
    secret = myradiussecret     # Shared secret
    require_message_authenticator = no
  }
  ```
  3. Save the file.
     
- **Step 4**: Configure the Aruba SSID to use external RADIUS server
  1. Select the SSID and click edit
  2. In the Security tab
    a. enable MAC authentication
    b. create a new authentication server if yours does not exist yet
    c. give it a name
    d. set the ip address of the RADIUS server
    e. set the shared secret from step 3.
    f. click ok

- **Step 5**: Testing the RADIUS server
  1. ssh into the RADIUS server
  2. Run the following:
     ```
     sudo freeradius -X
     ```
  3. Connect to the SSID from a machine that has been added to the MAC list
  4. Stop testing with:
     ```
     sudo pkill -9 freeradius
     sudo lsof -i :1812
     ```
  5. Enable freeradius:
     ```
     sudo systemctl enable freeradius
     sudo systemctl start freeradius
     ```
      
- **Step 6**: Adding a MAC to the RADIUS server
  1. open users file:
  ```
  sudo nano /etc/freeradius/3.0/users
  ```
  2. Add entries for each device MAC:
  ```
  # Format: MAC as username, password same as MAC (or blank)
  # do NOT include the colons
  AABBCCDDEEFF   Cleartext-Password := "AABBCCDDEEFF"
  ```
  3. Save the file.
  4. Run the following command to push the new users to the RADIUS server
  ```
  sudo systemctl kill -s HUP freeradius
  ```
