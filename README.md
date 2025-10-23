# 🧰 ubuntu-hybrid-gpu-fix

Fix **black screen** or **no display** issues on Ubuntu systems with **AMD + NVIDIA hybrid GPUs** (e.g., Ryzen + RTX).

---

## 🧩 Problem Statement

After installing or upgrading **Ubuntu (24.04 or later)** on systems with both **AMD and NVIDIA GPUs**, the desktop GUI may fail to load.

### ⚠️ Common Symptoms

- Both monitors stay **black** after GRUB.
- `journalctl` shows:
  ```bash
  (EE) open /dev/dri/card0: No such file or directory
  (EE) no devices detected

* `gdm3` fails to start with “no screens found”.
* Running `nvidia-smi` fails or hangs.
* Text mode login works, but no Xorg/Wayland session loads.

### 💥 Root Cause

The **NVIDIA driver** claims the framebuffer that should belong to AMD, breaking GDM/Xorg initialization.

Ubuntu’s NVIDIA packages auto-enable **Kernel Mode Setting (KMS)** for NVIDIA, which causes:

* Both GPUs trying to control the primary display
* Xorg failing with “no devices detected”
* Endless login loops or black screens

---

## ✅ Solution Summary

This project’s script automatically:

1. **Detects** AMD and NVIDIA PCI Bus IDs
2. **Backs up** existing Xorg, modprobe, and module-load configs
3. **Cleans up** broken NVIDIA configuration files
4. **Creates** a proper hybrid GPU setup:

   * AMD (`amdgpu`) → **Primary Display Driver**
   * NVIDIA (`nvidia`) → **Compute / PRIME Offload**
5. **Enables PRIME Render Offload**, so you can run apps on NVIDIA GPU with:

   ```bash
   __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>
   ```
6. **Rebuilds initramfs** and **updates grub**

---

## 🧠 Why This Works

* Forces `amdgpu` to be the only active framebuffer driver
* Ensures load order: `amdgpu` → `nvidia`
* Keeps NVIDIA PRIME functional without framebuffer conflict
* Adds explicit BusID mappings to avoid Xorg detection errors

---

## 🪄 Usage Guide

### 🔧 Step 1: Download and Run

```bash
wget https://raw.githubusercontent.com/nik0811/ubuntu-hybrid-gpu-fix/refs/heads/master/fix-hybrid-gpu.sh
chmod +x fix-hybrid-gpu.sh
sudo ./fix-hybrid-gpu.sh
```

### 🌀 Step 2: Reboot

```bash
sudo reboot
```

### 🧾 Step 3: Verify After Reboot

```bash
# Both drivers loaded
lsmod | egrep "amdgpu|nvidia"

# NVIDIA compute visible
nvidia-smi

# AMD drives display
glxinfo | grep "OpenGL renderer"

# NVIDIA available for offload
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo | grep "OpenGL renderer"
```

✅ **Expected results:**

* AMD → default renderer
* NVIDIA → available for offload

---

## 🧩 Example Output

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

## 🧠 Technical Notes

* Tested on **Ubuntu 24.04+ (Kernel ≥ 6.8)**
* Supports **GDM3**, **Xorg**, and **Wayland**
* Compatible NVIDIA drivers: **535 / 550 / 560 / 580 (beta)**
* Works with all **AMD + NVIDIA hybrid laptops / desktops**

---

## 🧰 Restore (if needed)

All modified files are backed up under:

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

## 🧪 Run an App on NVIDIA GPU

Example:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia blender
```

Verify which GPU renders:

```bash
glxinfo | grep "OpenGL renderer"
```

---

## 📁 Repository Structure

```
ubuntu-hybrid-gpu-fix/
├── fix-hybrid-gpu.sh       # Main script
├── README.md               # Documentation
└── LICENSE                 # (MIT)
```

---

## 🩹 Bonus Fix: Cursor IDE UI Frozen on AMD / Hybrid GPUs (Linux)

If **Cursor IDE** opens but the UI is **frozen / unclickable**, it’s due to an Electron Wayland rendering bug.

### ✅ Fix (Ubuntu / Debian)

1. Edit the desktop entry:

   ```bash
   sudo nano /usr/share/applications/cursor.desktop
   ```

2. Replace both `Exec=` lines with:

   ```ini
   Exec=env LIBGL_ALWAYS_SOFTWARE=1 /usr/share/cursor/cursor --no-sandbox --disable-gpu --use-gl=swiftshader --ozone-platform=wayland %F
   Exec=env LIBGL_ALWAYS_SOFTWARE=1 /usr/share/cursor/cursor --no-sandbox --disable-gpu --use-gl=swiftshader --ozone-platform=wayland --new-window %F
   ```

3. Update database:

   ```bash
   sudo update-desktop-database
   ```

4. Clear GPU cache:

   ```bash
   rm -rf ~/.config/Cursor/{GPUCache,Cache,'Code Cache'}
   ```

5. Launch Cursor from menu.

### 💡 Why This Works

* `LIBGL_ALWAYS_SOFTWARE=1` → forces CPU rendering
* `--disable-gpu` + `--use-gl=swiftshader` → bypasses GPU issues
* `--ozone-platform=wayland` → ensures stable input under Wayland

> To restore GPU acceleration later, remove `LIBGL_ALWAYS_SOFTWARE=1` and `--use-gl=swiftshader`.

---

## 🏁 License

MIT License — free to use, modify, and distribute.

---

## 🏆 Summary

| Component                                     | Role                      | Driver                 |
| --------------------------------------------- | ------------------------- | ---------------------- |
| AMD Radeon (iGPU)                             | Display / Desktop         | `amdgpu`               |
| NVIDIA RTX / GTX                              | Compute / CUDA / Offload  | `nvidia`, `nvidia_uvm` |
| Display Manager                               | GNOME GDM3 / Xorg         | ✅ Works                |
| Black screens?                                | ✅ Fixed                   |                        |
| `nvidia-smi`                                  | ✅ Works                   |                        |
| PRIME Offload (`__NV_PRIME_RENDER_OFFLOAD=1`) | ✅ Works                   |                        |
| Cursor IDE (Wayland)                          | ✅ Fixed (software render) |                        |

---

⭐ **Contributions welcome!**
If this saved you hours of frustration, consider giving the repo a ⭐ on GitHub.
