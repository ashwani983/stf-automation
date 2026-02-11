# STF Automation - Project Structure

## 📁 Directory Structure

```
stf-automation/
├── README.md                  # Complete documentation with installation & usage guides
├── PROJECT_STRUCTURE.md       # This file - project overview
├── .env                       # Environment variables for Docker setup
├── docker-compose.yml         # Docker Compose configuration for STF stack
│
├── install.sh                 # Unified installation script (Docker or Manual)
├── start.sh                   # Unified script to start STF (Docker or Manual)
└── stop.sh                    # Unified script to stop STF (Docker or Manual)
```

## 📄 File Descriptions

### Documentation
- **README.md**: Comprehensive guide covering both installation methods, usage, configuration, and troubleshooting
- **PROJECT_STRUCTURE.md**: This file - provides project overview and quick reference

### Configuration Files
- **.env**: Docker environment variables (PUBLIC_IP, ports, etc.)
- **docker-compose.yml**: Defines STF, RethinkDB, and ADB services for Docker

### Installation & Operation Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `install.sh` | Install STF using Docker or manually | `./install.sh` |
| `start.sh`   | Start all STF services       | `./start.sh` |
| `stop.sh`    | Stop all STF services        | `./stop.sh` |


## 🚀 Quick Start Guide

```bash
# 1. Run the installer and choose your preferred method (Docker or Manual)
./install.sh

# 2. (Optional, for Docker) Edit .env to set your PUBLIC_IP
nano .env

# 3. Start services
./start.sh

# 4. Access STF at http://localhost:7100
```

## 🎯 Key Features

### Docker Installation
- ✅ **Isolated environment** - No system-wide dependencies
- ✅ **Easy cleanup** - Remove everything with `docker compose down -v`
- ✅ **Reproducible** - Same environment everywhere
- ✅ **Quick setup** - One command installation
- ✅ **Multiple instances** - Can run different versions

### Manual Installation
- ✅ **Better performance** - Direct hardware access
- ✅ **Systemd integration** - Auto-start on boot
- ✅ **More control** - Full customization
- ✅ **Production ready** - Service management
- ✅ **Lower overhead** - No containerization layer

## 🔍 What Each Component Does

### STF Components
- **STF App**: Main web application for device management
- **RethinkDB**: Database for storing device info, users, and sessions
- **ADB Server**: Communicates with Android devices via USB

### Installation Process

The `install.sh` script will guide you through either the Docker or Manual installation process.

#### Docker Installation
1. Installs Docker & Docker Compose
2. Installs ADB on host
3. Sets up USB permissions
4. Pulls Docker images:
   - `rethinkdb:2.4`
   - `devicefarmer/stf:latest`
   - `devicefarmer/adb:latest`

#### Manual Installation
1. Installs system dependencies:
   - cmake, graphicsmagick
   - libzmq, protobuf
   - yasm, pkg-config
   - ADB, bzip2
2. Installs Node.js 20.x
3. Installs RethinkDB
4. Clones STF repository
5. Installs NPM dependencies
6. Creates systemd services
7. Configures USB permissions

## 🛠️ Customization

### Docker Configuration

**Edit `.env` file:**
```bash
STF_PUBLIC_IP=192.168.1.100  # Your machine's IP
```

**Edit `docker-compose.yml`:**
- Change port mappings
- Adjust resource limits

### Manual Configuration

**Edit systemd services:**
```bash
sudo nano /etc/systemd/system/stf.service
sudo systemctl daemon-reload
sudo systemctl restart stf
```

**Common STF options:**
```bash
stf local --public-ip 192.168.1.100 \
          --port 7100 \
          --allow-remote
```

## 📊 Service Architecture

### Docker Stack
```
┌─────────────────────────────────────────┐
│           Docker Host                   │
│  ┌────────────┐  ┌─────────────┐       │
│  │ STF App    │  │ RethinkDB   │       │
│  │ Port: 7100 │  │ Port: 28015 │       │
│  └────────────┘  └─────────────┘       │
│  ┌────────────┐                         │
│  │ ADB Server │                         │
│  │ Port: 5037 │                         │
│  └────────────┘                         │
│  USB Devices: /dev/bus/usb              │
└─────────────────────────────────────────┘
```

### Manual Installation
```
┌─────────────────────────────────────────┐
│         Host System (Ubuntu)            │
│  ┌────────────────────────────────┐     │
│  │    Systemd Services            │     │
│  │  ┌──────────────────────────┐  │     │
│  │  │ stf-rethinkdb.service    │  │     │
│  │  └──────────────────────────┘  │     │
│  │  ┌──────────────────────────┐  │     │
│  │  │ stf.service              │  │     │
│  │  └──────────────────────────┘  │     │
│  └────────────────────────────────┘     │
│  USB Devices: /dev/bus/usb              │
└─────────────────────────────────────────┘
```

## 🔗 Access Points

After successful installation:

| Service | URL | Purpose |
|---------|-----|---------|
| STF Web Interface | http://localhost:7100 | Main application |
| RethinkDB Admin | http://localhost:8080 | Database management |
| ADB Server | localhost:5037 | Device communication |

**Default Credentials:**
- Email: `administrator@fakedomain.com`

## 🧪 Testing the Setup

```bash
# Check if services are running (Docker)
docker compose ps

# Check if services are running (Manual)
sudo systemctl status stf
sudo systemctl status stf-rethinkdb

# Check connected devices
adb devices

# View logs (Docker)
docker compose logs -f stf

# View logs (Manual)
sudo journalctl -u stf -f
```

## 🔄 Maintenance

### Docker
```bash
# Update images
docker pull devicefarmer/stf:latest
docker compose up -d

# Backup data (if using volumes)
# You need to define a backup strategy for your named volumes.

# Clean everything
docker compose down -v
```

### Manual
```bash
# Update STF
cd ~/Desktop/Workspace/stf
git pull
npm install
sudo systemctl restart stf

# Backup RethinkDB
rethinkdb dump -f backup.tar.gz
```

## 📞 Support

- **Documentation**: See README.md
- **STF Issues**: https://github.com/DeviceFarmer/stf/issues
- **STF Docs**: https://github.com/DeviceFarmer/stf/blob/master/README.md

## 🎓 Learning Resources

1. Start with the `install.sh` script.
2. Read README.md for detailed guides.
3. Experiment with connecting devices.
4. Check STF API documentation for automation.
5. Explore deployment options for production.

---

**Version**: 2.0
**Last Updated**: 2026-02-11
**Author**: Automated Setup Scripts for STF
