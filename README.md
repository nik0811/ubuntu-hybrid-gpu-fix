# 🧰 ubuntu-hybrid-gpu-fix

### 🧩 Problem Statement

After Installing or upgrading Ubuntu (24.04 or similar), systems with **both AMD and NVIDIA GPUs** may fail to boot into GUI.
Common symptoms:

* Both monitors stay **black** after GRUB.
* `journalctl` shows:

  ```
  (EE) open /dev/dri/card0: No such file or directory
  (EE) no devices detected
  ```
* `gdm3` fails to start with “no screens found”.
* Running `nvidia-smi` fails or hangs.
* Sometimes text mode login works but no Xorg/Wayland session loads.

This typically happens when:

* The **NVIDIA kernel driver** reclaims the display (framebuffer) from AMD.
* `/dev/dri/card0` gets assigned to NVIDIA instead of AMD.
* Ubuntu upgrades rewrite `/etc/modprobe.d/nvidia-graphics-drivers-kms.conf` to `modeset=1`, causing GDM and Xorg to bind to the wrong GPU.

---

### 🔍 Root Cause

Ubuntu’s NVIDIA package auto-enables **kernel mode setting (KMS)** for NVIDIA by default.
On systems with both **AMD iGPU** (for display) and **NVIDIA dGPU** (for compute/rendering), this causes:

* Both GPUs to claim the primary display.
* Xorg to fail with “no devices detected”.
* `gdm3` or `lightdm` to loop or show blank screens.

---

### ✅ Solution Summary

This script:

1. **Auto-detects AMD and NVIDIA PCI Bus IDs.**
2. **Backs up** existing Xorg, modprobe, and module-load configuration files.
3. **Cleans old blacklists** and broken NVIDIA config files.
4. **Creates a correct hybrid GPU configuration**:

   * AMD (`amdgpu`) is the **Primary Display Driver**.
   * NVIDIA (`nvidia`) is used for **compute / PRIME offload** only.
5. **Enables PRIME Render Offload** — so apps can use the NVIDIA GPU with:

   ```bash
   __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>
   ```
6. **Updates initramfs and grub** so changes persist after reboot.

---

### 🧠 Why This Works

* Forces `amdgpu` to be the only device with an active framebuffer.
* Loads both drivers in the correct order (`amdgpu` → `nvidia`).
* Keeps `modeset=1` for PRIME but avoids NVIDIA binding `/dev/dri/card0`.
* Configures Xorg to explicitly use correct `BusID`s to avoid autodetect conflicts.

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

✅ You should see AMD as default renderer and NVIDIA as offload renderer.

---

### 🧩 Example Output

```bash
$ lsmod | egrep "amdgpu|nvidia"
amdgpu               1234567  8
nvidia              9876543  68 nvidia_uvm,nvidia_modeset,nvidia_drm

$ nvidia-smi
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 550.95.05    Driver Version: 550.95.05    CUDA Version: 12.5     |
| GPU Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| NVIDIA RTX 3090 Off          | 00000000:01:00.0 Off |                  N/A |
+-----------------------------------------------------------------------------+

$ glxinfo | grep "OpenGL renderer"
OpenGL renderer string: AMD Radeon Graphics (amdgpu)
```

---

### 🧠 Technical Notes

* Works on Ubuntu 24.04 with systemd, GDM3, and kernel ≥ 6.8.
* Supports AMD + NVIDIA combinations (e.g., Ryzen + RTX).
* Tested with drivers: 535, 550, 560 and 580 beta.
* Compatible with both Xorg and Wayland sessions.

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

### 🧪 To Force App to Use NVIDIA GPU

For example, to run Blender or Stable Diffusion on NVIDIA GPU:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia blender
```

To verify which GPU renders an app:

```bash
glxinfo | grep "OpenGL renderer"
```

---

### 🧰 Repository Structure

```
ubuntu-hybrid-gpu-fix/
├── fix-hybrid-gpu.sh       # main script
├── README.md               # documentation (this file)
└── LICENSE                 # optional (MIT)
```

---

### 🏁 License

MIT License — free to use, modify, and distribute.

---

## 🏆 Summary

| Component                                      | Role                     | Driver                 |
| ---------------------------------------------- | ------------------------ | ---------------------- |
| AMD Radeon (iGPU)                              | Display / Desktop        | `amdgpu`               |
| NVIDIA RTX / GTX                               | Compute / CUDA / Offload | `nvidia`, `nvidia_uvm` |
| Display Manager                                | GNOME GDM3 / Xorg        | Works normally         |
| Black screens?                                 | ✅ Fixed                  |                        |
| `nvidia-smi`                                   | ✅ Works                  |                        |
| Hybrid offload (`__NV_PRIME_RENDER_OFFLOAD=1`) | ✅ Works                  |                        |

---
