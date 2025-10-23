---

# 🧰 ubuntu-hybrid-gpu-fix

### 🧩 Problem Statement

After installing or upgrading **Ubuntu (24.04 or similar)** on systems with **both AMD and NVIDIA GPUs**, the desktop GUI may fail to load.

**Common symptoms:**

- Both monitors stay **black** after GRUB.
- `journalctl` shows:
  ```bash
  (EE) open /dev/dri/card0: No such file or directory
  (EE) no devices detected
````

* `gdm3` fails to start with “no screens found”.
* Running `nvidia-smi` fails or hangs.
* Text mode login works, but no Xorg/Wayland session loads.

**Root cause:**
The NVIDIA driver claims the display output (framebuffer) that should belong to AMD, breaking GDM/Xorg initialization.

---

### 🔍 Root Cause

Ubuntu’s NVIDIA package auto-enables **kernel mode setting (KMS)** for NVIDIA by default.
On systems with **AMD iGPU** (display) and **NVIDIA dGPU** (compute), this results in:

* Both GPUs trying to control the primary display.
* Xorg failing with “no devices detected”.
* Endless login loops or black screens.

---

### ✅ Solution Summary

This project’s script automatically:

1. **Detects AMD and NVIDIA PCI Bus IDs**
2. **Backs up** current Xorg, modprobe, and module-load configuration files
3. **Cleans old or broken NVIDIA configs**
4. **Creates a correct hybrid GPU configuration**:

   * AMD (`amdgpu`) = **Primary Display Driver**
   * NVIDIA (`nvidia`) = **Compute / PRIME Offload**
5. **Enables PRIME Render Offload**
   You can then launch apps on the NVIDIA GPU using:

   ```bash
   __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>
   ```
6. **Rebuilds initramfs and updates grub**

---

### 🧠 Why This Works

* Forces `amdgpu` to be the only active framebuffer driver.
* Ensures correct module load order: `amdgpu` → `nvidia`.
* Keeps `modeset=1` for NVIDIA PRIME while preventing framebuffer conflicts.
* Creates explicit Xorg BusID mappings to avoid auto-detect failures.

---

### 🪄 Script Usage

#### 🔧 1. Download and Run

```bash
wget https://raw.githubusercontent.com/nik0811/ubuntu-hybrid-gpu-fix/refs/heads/master/fix-hybrid-gpu.sh
chmod +x fix-hybrid-gpu.sh
sudo ./fix-hybrid-gpu.sh
```

#### 🌀 2. Reboot

```bash
sudo reboot
```

#### 🧾 3. Verify After Reboot

```bash
# both drivers loaded
lsmod | egrep "amdgpu|nvidia"

# NVIDIA compute visible
nvidia-smi

# AMD drives display
glxinfo | grep "OpenGL renderer"

# NVIDIA available for offload
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo | grep "OpenGL renderer"
```

✅ Expected:

* AMD as default renderer
* NVIDIA available for offload rendering

---

### 🧩 Example Output

```bash
$ lsmod | egrep "amdgpu|nvidia"
amdgpu               1234567  8
nvidia              9876543  68 nvidia_uvm,nvidia_modeset,nvidia_drm

$ nvidia-smi
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 550.95.05    Driver Version: 550.95.05    CUDA Version: 12.5     |
| GPU Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC  |
| NVIDIA RTX 3090 Off          | 00000000:01:00.0 Off |                  N/A  |
+-----------------------------------------------------------------------------+

$ glxinfo | grep "OpenGL renderer"
OpenGL renderer string: AMD Radeon Graphics (amdgpu)
```

---

### 🧠 Technical Notes

* Works on Ubuntu 24.04+ (kernel ≥ 6.8)
* Supports GDM3, Xorg, and Wayland
* Compatible with driver versions: **535 / 550 / 560 / 580 (beta)**
* Supports all AMD + NVIDIA hybrid systems (Ryzen + RTX, etc.)

---

### 🧰 Restore (if needed)

All files modified by the script are backed up under:

```
/root/hybrid-gpu-backup-YYYYMMDD-HHMMSS/
```

To restore:

```bash
sudo cp -a /root/hybrid-gpu-backup-*/{xorg.conf.d,modprobe.d,modules-load.d} /etc/
sudo update-initramfs -u -k all
sudo reboot
```

---

### 🧪 Force an App to Use NVIDIA GPU

Example:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia blender
```

Verify which GPU renders:

```bash
glxinfo | grep "OpenGL renderer"
```

---

### 📁 Repository Structure

```
ubuntu-hybrid-gpu-fix/
├── fix-hybrid-gpu.sh       # Main script
├── README.md               # Documentation (this file)
└── LICENSE                 # Optional (MIT)
```

---

## 🩹 Fix: Cursor IDE Window Opens but UI Is Frozen on AMD / Hybrid GPUs (Linux)

If Cursor opens but you **can’t click or type anywhere**, it’s caused by
**Electron’s Wayland rendering bug** on AMD (Mesa) or hybrid GPU systems.

#### ✅ Solution (Ubuntu / Debian)

1. Open the Cursor desktop launcher file:

   ```bash
   sudo nano /usr/share/applications/cursor.desktop
   ```

2. Replace both existing `Exec=` lines with:

   ```ini
   Exec=env LIBGL_ALWAYS_SOFTWARE=1 /usr/share/cursor/cursor --no-sandbox --disable-gpu --use-gl=swiftshader --ozone-platform=wayland %F
   Exec=env LIBGL_ALWAYS_SOFTWARE=1 /usr/share/cursor/cursor --no-sandbox --disable-gpu --use-gl=swiftshader --ozone-platform=wayland --new-window %F
   ```

3. Refresh desktop database:

   ```bash
   sudo update-desktop-database
   ```

4. Clear any cached GPU data:

   ```bash
   rm -rf ~/.config/Cursor/GPUCache ~/.config/Cursor/Cache ~/.config/Cursor/'Code Cache'
   ```

5. Launch **Cursor** from the application menu.

#### 💡 Why this works

* `LIBGL_ALWAYS_SOFTWARE=1` → Forces pure software rendering (no GPU driver issues)
* `--disable-gpu` & `--use-gl=swiftshader` → Use Chromium’s CPU-based renderer
* `--ozone-platform=wayland` → Enables stable input handling under Wayland

This fix ensures Cursor runs smoothly on **AMD-only** and **hybrid AMD + NVIDIA** laptops using Wayland.

> If you update your GPU drivers or Mesa later and want hardware acceleration,
> simply remove `LIBGL_ALWAYS_SOFTWARE=1` and `--use-gl=swiftshader` from the `Exec=` lines.

---

### 🏁 License

MIT License — free to use, modify, and distribute.

---

## 🏆 Summary

| Component                                      | Role                      | Driver                 |
| ---------------------------------------------- | ------------------------- | ---------------------- |
| AMD Radeon (iGPU)                              | Display / Desktop         | `amdgpu`               |
| NVIDIA RTX / GTX                               | Compute / CUDA / Offload  | `nvidia`, `nvidia_uvm` |
| Display Manager                                | GNOME GDM3 / Xorg         | Works normally         |
| Black screens?                                 | ✅ Fixed                   |                        |
| `nvidia-smi`                                   | ✅ Works                   |                        |
| Hybrid offload (`__NV_PRIME_RENDER_OFFLOAD=1`) | ✅ Works                   |                        |
| Cursor IDE (Wayland)                           | ✅ Fixed (software render) |                        |

---
