# STF Automation - Unified Setup & Deployment

Automated and simplified installation scripts for **Smartphone Test Farm (STF)**. This project provides a single, unified script to install STF via Docker or manually.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)

## 🎯 Overview

This project provides a single, unified script to install and manage STF (Smartphone Test Farm), a web application for debugging Android devices remotely from your browser.

**Features:**
- ✅ **Unified Installer**: One script (`install.sh`) for both Docker and manual installations.
- ✅ **Simplified Controls**: Easy-to-use `start.sh` and `stop.sh` scripts.
- ✅ **Automated Docker Setup**: Installs Docker, pulls images, and configures the environment.
- ✅ **Automated Manual Setup**: Installs all dependencies, clones the STF repo, and sets up systemd services on Ubuntu/Debian.
- ✅ **USB device access configuration**.
- ✅ **RethinkDB database setup**.
- ✅ **Multi-device support**.

## 📦 Prerequisites

- Ubuntu/Debian based Linux distribution.
- Internet connection.
- `sudo` privileges.
- For manual installation: At least 4GB RAM and 10GB free disk space.

## 🚀 Quick Start

### Step 1: Make Scripts Executable

First, make the scripts executable:
```bash
chmod +x install.sh start.sh stop.sh
```

### Step 2: Run the Installer

Run the unified installer and choose your preferred method:
```bash
sudo ./install.sh
```
You will be prompted to choose between:
1.  **Docker (Recommended)**: For a clean, containerized installation.
2.  **Manual**: For a native installation with potentially better performance.

The script will handle the rest, from installing dependencies to pulling images or cloning the repository.

### Step 3: Start STF Services

Once the installation is complete, start all STF services with a single command:
```bash
sudo ./start.sh
```

### Step 4: Access STF

-   **STF Web Interface:** [http://localhost:7100](http://localhost:7100)
-   **RethinkDB Admin:** [http://localhost:8080](http://localhost:8080)
-   **Default Username:** `Administrator`
-   **Default Email:** `administrator@fakedomain.com`

## 🎮 Usage

### Starting and Stopping Services

-   **Start STF**:
    ```bash
    ./start.sh
    ```
-   **Stop STF**:
    ```bash
    ./stop.sh
    ```

### Service Logs

-   **For Docker installations**:
    ```bash
    # View all logs
    docker compose logs -f

    # View specific service logs
    docker compose logs -f stf
    ```
-   **For Manual installations**:
    ```bash
    # Check service status
    sudo systemctl status stf
    sudo systemctl status stf-rethinkdb

    # View logs
    sudo journalctl -u stf -f
    ```

### Connecting Android Devices

1.  **Enable USB Debugging** on your Android device.
2.  **Connect the device** via USB.
3.  **Accept the authorization prompt** on your device.
4.  **Verify the device is connected**: `adb devices`
5.  The device should now appear in the STF web interface.

## ⚙️ Configuration

### Docker Configuration

-   **Public IP**: To access STF from other devices, edit the `.env` file and set the `STF_PUBLIC_IP` variable to your machine's IP address.
    ```bash
    nano .env
    ```
-   **Ports & Volumes**: For more advanced changes, you can modify the `docker-compose.yml` file.

### Manual Installation Configuration

-   The manual installation sets up `systemd` services. To customize the STF startup command, you can edit the service file:
    ```bash
    sudo nano /etc/systemd/system/stf.service
    ```
-   After making changes, reload the `systemd` daemon and restart the service:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart stf
    ```

## 🔧 Troubleshooting

### Device Not Showing Up

-   Run `adb devices` to check if the device is recognized by the host.
-   Ensure USB debugging is enabled and authorized.
-   Try a different USB cable or port.
-   Restart the ADB server: `adb kill-server && adb start-server`

### Docker Issues

-   **Permission Denied**: If you see Docker errors, you may need to run `sudo usermod -aG docker $USER` and then log out and back in.
-   **Container Won't Start**: Check the logs with `docker compose logs stf`.
-   **Port Conflict**: If a port is already in use, you can change it in the `.env` or `docker-compose.yml` file.

### Manual Installation Issues

-   **STF Won't Start**: Check the status of the services with `sudo systemctl status stf stf-rethinkdb` and view logs with `sudo journalctl -u stf -n 50`.
-   **RethinkDB Connection Error**: Ensure the `stf-rethinkdb` service is running and not blocked by a firewall.

## 🔐 Security Notes

-   STF is intended for use within a trusted, internal network.
-   The default setup uses mock authentication. For production, run STF behind a VPN or an authenticating reverse proxy (like Nginx).
-   Use dedicated test devices and accounts.

## 📚 Additional Resources

-   [STF GitHub Repository](https://github.com/DeviceFarmer/stf)
-   [STF Documentation](https://github.com/DeviceFarmer/stf/blob/master/README.md)
-   [STF Deployment Guide](https://github.com/DeviceFarmer/stf/blob/master/doc/DEPLOYMENT.md)

---

**Made with ❤️ for easier STF deployment**
